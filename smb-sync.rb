#!/usr/bin/env ruby
DOCUMENTATION = <<DOCEND
A simple script to synchronize content of SMB share over the Internet. 
Essentially, it automates following steps: 

 * (Optional) Establish an VPN connection
 * Mount a SMB share
 * 'rsync' files from SMB share to local directory
 * Umount previously mounted SMB share
 * (Optional) Shut down previously established VPN connection

## Configuration

To run this script non-interactively (which was the intention), you need
either to run it as root (NOT RECCOMENDED) or setup `sudo` to allow certain
command to run without asking for a password. This is unavoidable since
script needs to establish a VPN connetion (thus configure network) and mount
a filesystem. See section example for example of such `sudo` config. 

## Example 

Let assume we have a user `bob` who need to run this script to sync
data on share `//10.0.1.12/bob` accessed via OpenVPN connection
configured in `/etc/openvpn/bob-work.config`. 

First, we need to configure sudo:

    sudo visudo -f /etc/sudoers.d/bob-smb-sync

and add following:/bin/mount -t cifs

    Cmnd_Alias BOBSMBSYNC = /usr/sbin/openvpn --config /etc/openvpn/bob-work.config --user bob *, /bin/mount -t cifs //10.0.1.12/bob *, /bin/umount //10.0.1.12/bob

    bob bobhomecomputer = (root) NOPASSWD: BOBSMBSYNC

To actually synchronize the share but exclude all `*.bak` files, execute:

    /path/to/smb-sync.rb \\
        --src //10.0.1.12/bob \\      
        --dst /backups/bob/work \\
        --credentials /home/bob/.bob-work-credentials \\
        --ovpn-config /etc/openvpn/bob-work.config \\
        --opt=--exclude --opt=*.bak \\

When running this as a cronjob, you may want to add `--syslog` to route 
log messages via system logger. 

DOCEND


require 'tmpdir'
require 'fileutils'
require 'optparse'

if not $LOGGER then
  if STDOUT.tty? then
    require 'logger'
    $LOGGER = Logger.new(STDOUT)
    $LOGGER.level = Logger::INFO  
  else 
    require 'syslog/logger'
    $LOGGER = Syslog::Logger.new($0)    
  end
end

$:.push(File.dirname($0))
require 'scriptutils'

module CiscoVPN
  class Client
    def initialize(config)
      @config = config
    end
  

    # Start (Cisco) VPN connection, return true if connections has
    # been established, false otherwise
    def start() 
      cmd = "sudo -n /usr/sbin/vpnc-connect #{@config}"            
      if ScriptUtils::sh(cmd) then          
        at_exit { stop() }
        $LOGGER.info("VPN connection established")
        return true
      else      
        $LOGGER.error("Failed command was: #{cmd}")
        $LOGGER.error("Failed to establish a VPN connection (vpnc-connect command failed)")
        return false;
      end
    end

    # Stop (Cisco) VPN connection
    def stop() 
      cmd = "sudo -n /usr/sbin/vpnc-disconnect"            
      if ScriptUtils::sh(cmd) then          
        $LOGGER.info("(Cisco VPN connection shut down")
      else
        $LOGGER.error("Failed shutdown Cisco VPN connection")
        $LOGGER.error("Failed command was: #{cmd}")        
      end
    end

  end # class Client
end

module OpenVPN
  class Client
    # Statuses
    STATE_CONNECTING   = 1
    STATE_CONNECTED    = 2
    STATE_DISCONNECTED = 4

    TIMEOUT = 30#sec

    def initialize(config) 
      @config = config
      @rundir = Dir.mktmpdir("openvpn", "/tmp"); at_exit { FileUtils.remove_entry ( @rundir ) }
      @pidfile = File.join(@rundir, 'openvpn.pid')
      @logfile = File.join(@rundir, 'openvpn.log')      
      FileUtils.touch(@logfile)
    end

    # Start OpenVPN connection. Return true if connection has been
    # (likely) established, false otherwise.
    def start() 
      if not File.directory? @rundir then
        $LOGGER.error("Failed to create temporary directory (#{@rundir}")
        return false;
      end
      # Start the client in daemon mode
      user = `id -un`.chop
      cmd = "sudo -n /usr/sbin/openvpn --config #{@config} --user #{user} --daemon --writepid #{@pidfile} --log #{@logfile}"            
      if not ScriptUtils::sh(cmd) then          
        $LOGGER.error("Failed to establish a VPN connection (openvpn command failed)")
        $LOGGER.error("Failed command was: #{cmd}")
        $LOGGER.error("Run  directory was: #{@rundir}")
        return false;
      end
      if ScriptUtils::dryrun
        return true
      end
      # Wait 3 sec to give openvpn process a chance to write its pid.
      sleep(3)
      if not File.exist? @pidfile or pid() == nil then
        $LOGGER.error("Failed to establish a VPN connection (pidfile not found)")
        return false;
      end      
      slept = 0      
      while true do
        slept += 5;
        sleep(5);
        s = state()
        if s == STATE_CONNECTED then
          at_exit { stop() }    
          $LOGGER.info("VPN connection established (waiting 5 secs to stabilize)")
          sleep(5)
          return true;
        elsif s == STATE_DISCONNECTED then
          $LOGGER.error("Failed to establish a VPN connection (disconnected)")
          return false
        elsif slept >= TIMEOUT then
          $LOGGER.error("Failed to establish a VPN connection (not connected within #{TIMEOUT}sec)")
          return false
        else
          $LOGGER.info("VPN still connecting, waiting...")
        end        
      end
    end

    def pid() 
      return File.open(@pidfile).read().chop().to_i
    end

    def state() 
      if not File.exist? @pidfile then
        return STATE_DISCONNECTED
      end
      if not File.exist? @logfile then
        return STATE_DISCONNECTED
      end
      if not File.readable_real? @logfile then
        return STATE_CONNECTING
      end
      connected = false
      File.open(@logfile).each do | line | 
        if line.include? "Initialization Sequence Completed"
          connected = true
        elsif line.include? "SIGTERM received"
          connected = false
        end
      end
      if connected then
        return STATE_CONNECTED
      else 
        return STATE_CONNECTING
      end
    end

    def stop() 
      if state() != STATE_DISCONNECTED then
        Process.kill("TERM", pid())   
        $LOGGER.info("OpenVPN connection shut down")
      end
    end
  end
end

module JV
  module Scripts    
    class Smb_sync
      STATUS_SUCCESS = 0
      STATUS_FAILED = 127

      # Mount a SMB share to a temporary directory. Return
      # true if mount was successfully, false otherwuse.       
      def smb_share_mount(share, mountpoint, credentials)        
        user = `id -un`.chop                
        cmd = "sudo -n mount -t cifs #{share} #{mountpoint} -o credentials=#{credentials},uid=#{user},forceuid"
        if not ScriptUtils::sh(cmd) then          
          $LOGGER.error("Failed to mount #{share} (mount command failed)")
          $LOGGER.error("Failed command was: #{cmd}")
          return false
        end        
        at_exit { smb_share_umount(share) }
        # Following is just a hack to wait until filesystem
        # is actually mounted. Otherwise we may get 
        #
        #    mount error(115): Operation now in progress
        #
        ScriptUtils::sh("ls #{mountpoint}")
        if not smb_share_mounted?(share) then
          $LOGGER.error("Failed to mount #{share} (mount not listed in /etc/mtab)")
          return false
        end
        return true;
      end

      def smb_share_mounted?(share) 
        if ScriptUtils::dryrun then
          return true
        end
        File.open('/etc/mtab').each do | line | 
          if line.include? share
            return true
          end
        end
        return false
      end

      def smb_share_umount(share)
        if not smb_share_mounted?(share)
          return 
        end
        cmd = "sudo -n umount #{share}"        
        if not ScriptUtils::sh(cmd) then          
          $LOGGER.error("Failed to umount #{share} mounted to #{mountpoint} (umount command failed)")          
          $LOGGER.error("Failed command was: #{cmd}")
        end        
      end

      def sync(share, src, dst, allowpartial, opts)
        $LOGGER.info("Syncing #{share} (to #{dst})")
      	debug_opts = ''
      	if $LOGGER.level == Logger::DEBUG then
      	  debug_opts = '--progress'
      	end
        cmd = "rsync -r -t #{debug_opts} #{opts.join(' ')} #{src}/* #{dst}"
        if not ScriptUtils::sh(cmd) then
          exitstatus = $?.exitstatus
          if ! (exitstatus == 23 && allowpartial == true) then
            $LOGGER.error("Failed to umount sync files (rsync command failed, exitstatus #{exitstatus})")          
            $LOGGER.error("Failed command was: #{cmd}")
          end
        else
          $LOGGER.info("Synced #{share} (to #{dst})")
        end
      end

      def run(*args, options)        
        smb_share = options[:smbshare] || nil
        smb_creds = options[:smbcreds] || nil                

        dstdir = options[:dstdir] || nil                

        if not dstdir then
          $LOGGER.error("Destination directory not specified, use --dst")
          return STATUS_FAILED 
        end
        if not File.exist?(dstdir) then
          $LOGGER.error("Destinatim directory does not exist")
          return STATUS_FAILED
        end
        if not File.directory?(dstdir) then
          $LOGGER.error("Destinatim directory does not a directory")
          return STATUS_FAILED
        end

        if not smb_share then
          $LOGGER.error("Source SMB share not specified, use --src")
          return STATUS_FAILED
        end

        if not smb_creds then
          $LOGGER.error("SMB credentials not specified, use --credentials")
          return STATUS_FAILED
        end

        ovnp_conf = options[:ovpnconf] || nil        
        vnpc_conf = options[:vpncconf] || nil        
        if ovnp_conf != nil and vnpc_conf != nil then
          $LOGGER.error("Both --ovpn-config and --vpnc-config specified, at most one is allowed")
          return STATUS_FAILED
        end

        # Establish an VPN connection if required        
        if ovnp_conf then
          vpn = OpenVPN::Client.new(ovnp_conf)
          if not vpn.start() then
            return STATUS_FAILED
          end          
        elsif vnpc_conf then
          vpn = CiscoVPN::Client.new(vnpc_conf)
          if not vpn.start() then
            return STATUS_FAILED
          end          
        else
          $LOGGER.info("VPN connection not established as no --ovpn-config nor --vpnc-config given")
        end

        # Mount         
        srcdir = Dir.mktmpdir("smb-sync", "/tmp")
        #at_exit (remove directory)
        if not smb_share_mount(smb_share, srcdir, smb_creds) then
          return STATUS_FAILED
        end        
        begin
          sync(smb_share, srcdir, dstdir, (options[:allowpartial] || false), (options[:rsyncopts] || []))
        ensure
          smb_share_umount(smb_share)
        end
        return STATUS_SUCCESS
      end
    end # class Smb_sync
  end # module JV::Scripts    
end # module JV

def run!() 
  opts = {}
  optparser = OptionParser.new do | optparser |
    optparser.banner = "Usage: $0 [options] --src SHARE --dst DIRECTORY"

    optparser.on('--ovpn-config CONFIG', "Use given OpenVPN config file to establish a VPN connection. Optional.") do | value |
      opts[:ovpnconf] = value
    end

    optparser.on('--vpnc-config CONFIG', "Use given Cisco VPN config file to establish a VPN connection. Optional.") do | value |
      opts[:vpncconf] = value
    end

    optparser.on('--src SHARE', "Synchronize deta from given SHARE. Mandatory.") do | value |
      opts[:smbshare] = value
    end      

    optparser.on('--dst DIRECTORY', "Synchronize data to given DIRECTORY. Mandatory.") do | value |
      opts[:dstdir] = value
    end

    optparser.on('--credentials CREDENTIALS', "Use given CREDENTIALS to authenticate to the SHARE. Mandatory") do | value |
      opts[:smbcreds] = value
    end

    optparser.on('--allow-partial-transfer', "Do not fail if rsync reports partial transfer due to an error (exitcode 23)") do | value | 
      opts[:allowpartial] = true
    end

    optparser.on('-o', '--opt=OPTION', "Pass following option to rsync") do | value | 
      opts[:rsyncopts] = (opts[:rsyncopts] || []) << "'#{value}'"
    end

    optparser.on('--dry-run', "Process as normal but do not actually push or pull changes. Implies --verbose") do
      opts[:dryrun] = true
      if ($LOGGER.level > Logger::INFO) 
        $LOGGER.level = Logger::INFO
      end
      ScriptUtils::dryrun = true
    end

    optparser.on('--verbose', "Print more information during processing") do
      if ($LOGGER.level > Logger::INFO) 
        $LOGGER.level = Logger::INFO
      end
    end

    optparser.on('--debug', "Print debug messages during processing") do
      $LOGGER.level = Logger::DEBUG
      begin
        require 'pry'
        require 'pry-byebug'
      rescue LoadError => ex
        $LOGGER.info "Gems pry and/or pry-byebug not installed, no interactive debugging available"
        $LOGGER.info "Run 'gem install pry pry-byebug' to install."
      end      
    end

    optparser.on('--syslog', "Log to syslog rather than to stdout") do
      require 'syslog/logger'
      $LOGGER = Syslog::Logger.new($0)          
    end

    optparser.on('--help', "Prints this message") do
      puts DOCUMENTATION
      puts optparser.help()
      exit 0
    end
  end
  optparser.parse! 

  
  exit JV::Scripts::Smb_sync.new().run(ARGV, opts)
  
end

run! if __FILE__ == $0





