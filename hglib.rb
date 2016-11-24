# This file is not a standalone script. It is a kind
# of lightweight Mercurial library used by other scripts.

require 'uri'
require 'open3'
require 'shellwords'

# Following hack is to make hglib.rb working wit both jv:scripts and
# Smalltalk/X rakefiles. 
begin
  require 'rakelib/inifile'
rescue LoadError => ex
  begin
    require 'inifile'
  rescue LoadError => ex
    $LOGGER.error("Cannot load package 'inifile'")
    $LOGGER.error("Run 'gem install inifile' to install it")
    exit 1
  end
end

if not $LOGGER then
  if STDOUT.tty? or win32? then
    require 'logger'
    $LOGGER = Logger.new(STDOUT)
    $LOGGER.level = Logger::INFO  
  else 
    require 'syslog/logger'
    $LOGGER = Syslog::Logger.new($0)    
  end
end

module HG
  @@config = nil

  GLOBAL_OPTIONS= [:'cwd', :'repository', :'noninteractive', :'config', :'debug', :'debugger',
       :'encoding',:'encodingmode',:'traceback',:'time', :'profile',:'version', :'help',
       :'hidden' ]
  # Execute `hg` command with given positional arguments and
  # keyword arguments turned into command options. For example, 
  #
  #     HG::hg("heads", "default", cwd: '/tmp/testrepo')
  #
  # will result in executing
  # 
  #     hg --cwd '/tmp/testrepo' heads default
  #
  # In addition if block is passed, then the block is evaluate with
  # `hg` command exit status (as Process::Status) and (optionally)
  # with contents of `hg` command stdout and stderr. 
  # If no block is given, an exception is raised when `hg` command 
  # exit status IS NOT zero.
  def self.hg(command, *args, **options, &block)
    g_opts = []
    c_opts = []
    options.each do | k , v |       
      if v != false and v != nil
        o = k.size == 1 ? "-#{k}" : "--#{k}"                
        if GLOBAL_OPTIONS.include? k then                  
          if v.kind_of?(Array)
            v.each do | e |
              g_opts << o << (e == true ? '' : e)  
            end
          else
            g_opts << o << (v == true ? '' : v)
          end
        else
          if v.kind_of?(Array)
            v.each do | e |
              c_opts << o << (e == true ? '' : e)  
            end
          else
            c_opts << o << (v == true ? '' : v)
          end
        end
      end
    end
    c_opts.reject! { | e | e.size == 0 }
    cmd = ['hg'] + g_opts + [command] + c_opts + args      
    cmd_info = cmd.shelljoin.
                gsub(/username\\=\S+/, "username\\=***").
                gsub(/password\\=\S+/, "password\\=***")
    $LOGGER.debug("executing: #{cmd_info}")
    if defined? RakeFileUtils then
      puts cmd_info
    end
    if block_given? then
      stdout, stderr, status = Open3.capture3(*cmd)
      case block.arity
      when 1        
        yield status
      when 2        
        yield status, stdout
      when 3        
        yield status, stdout, stderr
      else
        raise Exception.new("invalid arity of given block")
      end
    else
      if not system(*cmd) then
        raise Exception.new("command failed: #{cmd.join(' ')}")
      end
    end    
  end

  def self.config()
    if @@config == nil
      files = Dir.glob('/etc/mercurial/hgrc.d/*.rc') + 
          [ '/etc/mercurial/hgrc' ,
          hgrc() ]  
      @@config = IniFile.new()
      files.each do | file |
        if File.exist?(file)
          $LOGGER.debug("Loading global config from \"#{file}\"")
          @@config.merge!(IniFile.new(:filename => file))
        end
      end  
    end
    return @@config
  end

  def self.hgrc()
  	return File.expand_path('~/.hgrc')
  end

  class Repository
    attr_accessor :path, :config

    # Clone a repository from given `uri` to given `directory`. 
    # Returns an `HG::Repository` instance representing the repository
    # clone. 
    # If `noupdate` is true, working copy is not updated, i.e., will be
    # empty. Use this when you're going to issue `update(rev)` shortly after.
    #
    def self.clone(uri, directory, noupdate: false)
      host = URI(uri).host
      # When cloning over LAN, use --uncompressed option
      # as it tends to be faster if bandwidth is good (1GB norm
      # these days) amd saves some CPU cycles.      
      uncompressed = false
      if host
        require 'resolv'
        addr = Resolv.getaddress(host)
        # Really poor detection of LAN, but since this is an 
        # optimization, getting this wrong does not hurt.         
        uncompressed = (addr.start_with? '192.168.') or (addr.start_with? '10.10.')
      end
      if noupdate then
        HG::hg("clone", uri, directory, uncompressed: uncompressed, noupdate: true)
      else
        HG::hg("clone", uri, directory, uncompressed: uncompressed)
      end
      return HG::Repository.new(directory)
    end

    # Initializes an empty repository in given directory. Returns an 
    # `HG::Repository` instance representing the created (empty) repository.
    def self.init(directory)
      HG::hg("init", directory)
      return HG::Repository.new(directory)
    end

    # Like HG::hg, but passes --cwd @path
    def hg(command, *args, **options, &block)
      options[:cwd] = @path
      HG::hg(command, *args, **options, &block)
    end

    def hgrc() 
      return File.join(@path, '.hg', 'hgrc')
    end

    def initialize(directory)
      @path = directory
      config_file = hgrc()
      if File.exist? ( config_file ) 
        $LOGGER.debug("Loading repository config from \"#{config_file}\"")
        @config = HG::config().merge(IniFile.new(:filename => config_file))
      else
        @config = HG::config()
      end
    end

    # Return a hashmap with defined paths (alias => uri)
    def paths() 
      return @config['paths'].clone
    end

    # Set paths for given repository
    def paths=(paths)
      config = IniFile.new(:filename => self.hgrc())
      config['paths'] = paths
      config.write()
    end

    def log(revset, template = "{node|short}\n")      
      log = []
      hg("log", rev: revset, template: template) do | status, out |     
        if status.success?
          puts out
          log = out.split("\n")
        end
      end
      return log
    end

    # Return changeset IDs of all head revisions. 
    # If `branch` is given, return only heads in given
    # branch.
    def heads(branch = nil) 
      if branch then
        return log("head() and branch('#{branch}')")
      else
        return log("head()")
      end
    end

    # Return a hash "bookmark => revision" of all 
    # bookmarks. 
    def bookmarks(branch = nil)
      revset  = "bookmark()"
      revset += " and branch('#{branch}')" if branch
      bookmarks = {}
      self.log(revset, "{bookmarks}|{node|short}\n").each do | line |
        bookmark, changesetid = line.split("|")
        bookmarks[bookmark] = changesetid
      end
      return bookmarks
    end

    def pull(remote = 'default', user: nil, pass: nil, rev: nil, bookmarks: [])
      authconf = []
      if pass != nil then
        if user == nil then
          raise Exception.new("Password given but not username! Use user: named param to specify username.")
        end
        # If user/password is provided, make sure we don't have
        # username in remote URI. Otherwise Mercurial won't use 
        # password from config!
        uri = URI.parse(self.paths[remote] || remote)
        uri.user = nil
        uri = uri.to_s
        uri_alias = if self.paths.has_key? remote then remote else 'xxx' end
        authconf << "auth.#{uri_alias}.prefix=#{uri}"
        authconf << "auth.#{uri_alias}.username=#{user}"        
        authconf << "auth.#{uri_alias}.password=#{pass}"        
      end
      hg("pull", remote, config: authconf, rev: nil) do | status |
        if not status.success? then
          raise Exception.new("Failed to pull from #{remote} (exit code #{status.exitstatus})")
        end
      end
    end

    def push(remote = 'default', user: nil, pass: nil, rev: nil)
      authconf = []
      if pass != nil then
        if user == nil then
          raise Exception.new("Password given but not username! Use user: named param to specify username.")
        end
        # If user/password is provided, make sure we don't have
        # username in remote URI. Otherwise Mercurial won't use 
        # password from config!
        uri = URI.parse(self.paths[remote] || remote)
        uri.user = nil
        uri = uri.to_s
        uri_alias = if self.paths.has_key? remote then remote else 'xxx' end
        authconf << "auth.#{uri_alias}.prefix=#{uri}"
        authconf << "auth.#{uri_alias}.username=#{user}"        
        authconf << "auth.#{uri_alias}.password=#{pass}"        
      end
      hg("push", remote, config: authconf, rev: rev) do | status |
        if status.exitstatus != 0 and status.exitstatus != 1 then
          raise Exception.new("Failed to push to #{remote} (exit code #{status.exitstatus})")
        end
      end      
    end

    # Create a shared clone in given directory, Return a new
    # HG::Repository object on the shared clone
    def share(dst, rev = nil)
      if File.exist? dst then
        raise Exception.new("Destination file exists: #{dst}")
      end
      if rev == nil then
        rev = log('.')[0]
      end
      if not has_revision?(rev) 
        raise Exception.new("Revision #{rev} does not exist")
      end
      mkdir_p File.dirname(dst);
      HG::hg("share", path, dst, config: 'extensions.share=', noupdate: true, bookmarks: false)
      share = Repository.new(dst)
      share.update(rev);
      return share
    end

    # Updates the repository's working copy to given 
    # revision if given. If not, update to most-recent
    # head, as plain
    #
    #   hg update
    #
    # would do. 
    def update(rev = nil)
      if rev 
      if not has_revision? rev then
        raise Exception.new("Revision #{rev} does not exist")
      end
      hg("update", rev: rev)
      else
        hg("update")
      end
    end

    # Merge given revision. Return true, if the merge was
    # successful, false otherwise
    def merge(rev)
      if not has_revision? rev then
        raise Exception.new("Revision #{rev} does not exist")
      end
      hg("merge", rev) do | status |
        return status.success?
      end
    end

    def commit(message, user: nil)
      hg("commit", message: message, user: user)
    end

    def has_revision?(rev)
    	revs = log(rev)
    	return revs.size > 0      
    end

    # Lookup a repository in given `directory`. If found,
    # return it as instance of HG::Repository. If not,
    # `nil` is returned.
    def self.lookup(directory)
      return nil if not File.exist?(directory)
      repo_dir = directory
      while repo_dir != nil
        if HG::repository? repo_dir
          return Repository.new(repo_dir)
        end
        repo_dir_parent = File.dirname(repo_dir)
        if repo_dir_parent == repo_dir
          repo_dir = nil
        else 
          repo_dir = repo_dir_parent
        end
      end
    end    

    # Initializes and empty Mercurial repository in given `directory`
    def self.init(directory)
      FileUtils.mkdir_p File.dirname(directory)
      HG::hg("init", directory)
      return Repository.new(directory)
    end
  end # class Repository 

  # Return `true` if given `directory` is a root of mercurial
  # repository, `false` otherwise.
  def self.repository?(directory)
    return File.directory? File.join(directory, '.hg')
  end

  # Enumerate all repositories in given `directory`
  def self.forest(directory, &block)      
    if repository? directory  
      yield Repository.new(directory)
    end
    Dir.foreach(directory) do |x|
      path = File.join(directory, x)
      if File.directory? path       
        if x == "." or x == ".." or x == ".svn" or x == '.git'
          next    
        elsif File.directory?(path)
          forest(path, &block)
        end
      end
    end  
  end
end # module HG
