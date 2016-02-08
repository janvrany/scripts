#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND

CAVEATS
=======

Currently only tested on Linux and supports only CVS upstream, though 
fixing this would not be much of a work.

DOCEND

# Contents of default configuration sections
DEFAULT = <<DEFEND

[xpull]
# Configuration for hg-xpull, see
# 
#     https://bitbucket.org/janvrany/jv-scripts/src/tip/hg-xpull.rb
# 
# Repository from which to pull and convert changes. For now, 
# only CVS repositories are supported. Mandatory.
#
# repository = :pserver:cvs@cvs.smalltalk-x.de:/cvs/stx
# repository = :pserver:cvs@cvs.smalltalk-x.de:/cvs/stx

# For CVS repositories, a subdirectory within that CVS repo. Mandatory for CVS
# repositories. Ignored for all others.
#
# repository-subdir = stx/projects/tinytalk
# repository-subdir = stx/projects/tinytalk

[xpull-authormap]
# This section defines an authormap used when converting commits. Optional. 
# For more details see:
# 
#    https://www.mercurial-scm.org/wiki/ConvertExtension#A--authors_.2F_--authormap
#
# Format is <upstream name> = <converted name>, for example:
#
# jdoe = John Doe <john@doe.org>
# ivan = Ivan Ivanovic <ivan@ivanovic.home>

[xpull-branchmap]
# This section defines a banchmap used when converting commits. Optional. 
# For more details see:
# 
#    https://www.mercurial-scm.org/wiki/ConvertExtension#A--branchmap
#
# Format is <upstream branch> = <converted branch>. For CVS repositorues,
# the "main" branch is named MAIN. To pull commits from CVS upstream (no-branch)
# into mercurial branch say 'cvs_MAIN', use
#
# MAIN = cvs_MAIN

[automerge]
# Automatically merge pulled changes from specified mercurial branch (if exists) 
# to specified mercurial branch (if exists). The syntax is 
# 
# automerge = <from-branch>:<to branch>. 
#
# The example below will merge changed from branch `default` to branch `jv`. 
# If merge fails, issue a warning but proceed. Optional. 
#
# automerge = default:jv
# automerge = default:jv

DEFEND

require 'fileutils'
require 'tmpdir'
require 'optparse'
require 'logger'
require 'tempfile'
require 'open3'

include FileUtils

$LOGGER = Logger.new(STDOUT)
$LOGGER.level = Logger::WARN
$DRYRUN = false;

def sys(*cmd)
  $LOGGER.debug("executing: #{cmd.join(' ')}")
  retval = nil
  if not $DRYRUN 
    retval = system(*cmd)
  else
    retval = true
  end
  return retval
end

def syso(*cmd)
  $LOGGER.debug("executing: #{cmd.join(' ')}")
  retval = nil
  if not $DRYRUN 
    output, status = Open3.capture2(*cmd)
    return output, status.success? 
  else
    return '', true
  end  
end

def edit(file) 
  editors = [
    ENV['EDITOR'],
    "sensible-editor",
    "nano",
    "vim",
    "notepad.exe"
  ]
  editors.each do | editor |
    if editor 
      if sys "#{editor} #{file}"
        return
      end
    end
  end
  error("No suitable editor found, please define EDITOR environment variable");
end

module HG
  @@config = nil

  def self.CONFIG()
    if @@config == nil
      files = Dir.glob('/etc/mercurial/hgrc.d/*.rc') + 
          [ '/etc/mercurial/hgrc' ,
          File.expand_path('~/.hgrc') ]  
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

  def self.user_hgrc()   
  end

  class Repository
    attr_reader :root, :config

    def hgrc() 
      return File.join(@root, '.hg', 'hgrc')
    end

    def initialize(directory)
      @root = directory
      config_file = hgrc()
      if File.exist? ( config_file ) 
        $LOGGER.debug("Loading repository config from \"#{config_file}\"")
        @config = HG::CONFIG().merge(IniFile.new(:filename => config_file))
      else
        @config = HG::CONFIG()
      end
    end

    def log(revset, template = "{node|short}")
      out , success = syso "hg --cwd #{@root} log --rev \"#{revset}\" --template \"#{template}\\n\"" 
      if success
        return out.split("\n")
      else
        return []
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
      if not sys "hg --config extensions.share= share -U -B #{@root} #{dst}"
        raise Exception.new("Failed to make shared clone of #{@root}")
      end
      share = Repository.new(dst)
      share.update(rev);
      return share
    end

    # Updates the repository's working copy to given 
    # revision. 
    def update(rev)
      if not has_revision? rev then
        raise Exception.new("Revision #{rev} does not exist")
      end
      if not sys "hg --cwd #{@root} update -r #{rev}" then
        raise Exception.new("Failed to update working copy to revision '#{rev}'")
      end
    end

    # Merge given revision. Return true, if the merge was
    # successful, false otherwise
    def merge(rev)
      if not has_revision? rev then
        raise Exception.new("Revision #{rev} does not exist")
      end
      return sys "hg --cwd #{@root} merge #{rev}"
    end

    def commit(message)
      user_arg = ''
      if not @config['ui'].has_key? 'username' then
        user_arg = "--user 'Merge Script"
      end
      if not sys "hg --cwd #{@root} commit -m '#{message}' #{user_arg}" then
        raise Exception.new("Failed to commit")
      end
    end

    def has_revision?(rev)
      return sys "hg --cwd #{@root} log --rev \"#{rev}\" --template ''"
    end

    def self.lookup(directory)
      return nil if not File.exist?(directory)
      repo_dir = directory
      while repo_dir != nil
        if File.directory?(File.join(repo_dir, '.hg'))
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
  end # class Repository 
end # module HG


module HG
  class Repository 

  def xpull_configured?()
    return @config.has_section?('xpull')
  end

  def xpull_validate_configuration()
    xpull_remote_repo = nil
    xpull_remote_repo_subdir = nil
    xpull_remote_sandbox = nil
    authormap = nil
    branchmap = nil
    splicemap = nil
    xpull_remote_repo_is_cvs = false
    if not @config.has_section?('xpull')
      raise Exception.new("No xpull configured in #{@root}. Run --config to configure it")
      return
    end
    if not @config['xpull'].has_key?('repository')
      raise Exception.new("No xpull.repository configured for #{@root}")
      return
    end
    xpull_remote_repo = @config['xpull']['repository']      
    xpull_remote_repo_is_cvs = xpull_remote_repo.start_with?(':ext:') || xpull_remote_repo.start_with?(':pserver:')
    if xpull_remote_repo_is_cvs 
      if not @config['xpull'].has_key?('repository-subdir')
        raise Exception.new("No xpull.repository-subdir configured for CVS repository #{@xpull_remote_repo}")
        return
      end
    end
  end

  def xpull_automerge()
    if not @config['automerge'].has_key?('automerge') then
      return
    end
    from_branch, into_branch = @config['automerge']['automerge'].split(':')
    if from_branch == nil then 
      $LOGGER.warn("automerge: from_branch is nil")
      return
    end
    if not self.has_revision?(from_branch) then
      $LOGGER.warn("automerge: from branch \"#{from_branch}\" does not exit")
      return
    end
    if into_branch == nil then 
      $LOGGER.warn("automerge: into_branch is nil")
      return
    end
    if not self.has_revision?(into_branch) then
      $LOGGER.warn("automerge: info branch \"#{into_branch}\" does not exit")
      return
    end    
    tmp = Dir.mktmpdir()
    begin
      merge_wc = share("#{tmp}/x");
      merge_wc.update(into_branch);
      if merge_wc.merge(from_branch) then
        merge_wc.commit("Merge");
      end
    rescue
      rm_rf tmp
    end
  end

  def xpull()
    xpull_remote_repo = nil
    xpull_remote_repo_subdir = nil
    xpull_remote_sandbox = nil
    authormap = nil
    branchmap = nil
    splicemap = nil
    xpull_remote_repo_is_cvs = false

    begin
      xpull_validate_configuration()
    rescue => ex
      $LOGGER.error(ex.message)
      return
    end

    xpull_remote_repo = @config['xpull']['repository']
    xpull_remote_repo_is_cvs = xpull_remote_repo.start_with?(':ext:') || xpull_remote_repo.start_with?(':pserver:')
    if xpull_remote_repo_is_cvs 
      xpull_remote_repo_subdir = @config['xpull']['repository-subdir']
    end

    $LOGGER.info("Pulling changes from #{xpull_remote_repo}#{xpull_remote_repo_subdir ? ' subdirectory ' + xpull_remote_repo_subdir : ''} into #{@root}")

    begin
      # Conversion of a CVS repository needs a sandbox
      if xpull_remote_repo_is_cvs
        xpull_remote_sandbox = Dir.mktmpdir()
        mkdir_p xpull_remote_sandbox
        chdir xpull_remote_sandbox do 
          $LOGGER.debug("Creating sandbox for CVS repository #{xpull_remote_repo} in #{xpull_remote_sandbox}")
          if not sys "cvs -z9 -d #{xpull_remote_repo} co #{xpull_remote_repo_subdir}"
            $LOGGER.error("Cannot checkout #{xpull_remote_repo} subdirectory #{xpull_remote_repo_subdir}")
            return
          end
        end
      end

      if @config.has_section?('xpull-authormap') and not @config['xpull-authormap'].empty?
        authormap = Tempfile.new('authormap')
        $LOGGER.debug("Creating authormap in #{authormap.path}")
        authormap.open
          begin
          for k, v in @config['xpull-authormap']
            $LOGGER.debug("  #{k}=#{v}")
            authormap.write("#{k}=#{v}\n")
          end
        ensure
          authormap.close
        end 
      end

      if @config.has_section?('xpull-branchmap') and not @config['xpull-branchmap'].empty?
        branchmap = Tempfile.new('branchmap')
        $LOGGER.debug("Creating branchmap in #{branchmap.path}")
        branchmap.open
        begin
          for k, v in @config['xpull-branchmap']
            b = k
            if b == 'MAIN' and xpull_remote_repo_is_cvs
              b = ''
            end
            $LOGGER.debug("  #{b} #{v}")
            branchmap.write("#{b} #{v}\n")
          end
        ensure
          branchmap.close
        end 
      end
    
      cmd  = "hg --config convert.cvsps.cache=False --config extensions.convert= convert "
      cmd += (authormap ? ' --authors ' + authormap.path : '')
      cmd += (branchmap ? ' --branchmap ' + branchmap.path : '')
      cmd += (splicemap ? ' --splicemap ' + splicemap : '')
      cmd += " #{xpull_remote_sandbox}/#{xpull_remote_repo_subdir} #{@root}"

      if not sys(cmd)
        $LOGGER.error("Cannot xpull changes (hg convert failed)")
        return
      end
    ensure
      if xpull_remote_sandbox
        $LOGGER.debug("Cleaning up sandbox (#{xpull_remote_sandbox})")
        rm_rf xpull_remote_sandbox
      end
      if authormap 
        $LOGGER.debug("Cleaning up authormap (#{authormap.path})")
        rm authormap.path
      end
      if branchmap 
        $LOGGER.debug("Cleaning up branchmap (#{branchmap.path})")
        rm branchmap.path
      end
    end
  end
  end
end

def opt_parse_key_value(input)
  key, value = input.split('=')
  key.strip!
  value/strip!
  return key, value
end

def main()
  repository_dir = nil
  config = false
 
  optparse = OptionParser.new do | opts |
    opts.banner = "Usage: hg-xull.rb [--cwd DIRECTORY] [options]"
    opts.on('-C', '--cwd DIRECTORY', "(x)pull changes in repository in DIRECTORY") do | value |
      repository_dir = value
    end
    opts.on(nil, '--dry-run', "Process as normal but do not actually modify repository. Implies --verbose") do
      $DRYRUN = true
      if ($LOGGER.level > Logger::INFO) 
        $LOGGER.level = Logger::INFO
      end
    end
    opts.on(nil, '--verbose', "Print more information during processing") do
      if ($LOGGER.level > Logger::INFO) 
      $LOGGER.level = Logger::INFO
      end
    end
    opts.on(nil, '--debug', "Print debug messages during processing") do
      require 'pry'
      require 'pry-byebug'
      $LOGGER.level = Logger::DEBUG
    end

    opts.on(nil, '--config', "Spawns an editor to configure hg-xpull") do
      config = true
    end

    opts.on(nil, '--help', "Prints this message") do
      puts DOCUMENTATION
      puts optparse.help()
      exit 0
    end
  end
  optparse.parse!  

  begin
    require 'inifile'
  rescue LoadError => ex
    $LOGGER.error("Cannot load package 'inifile'")
    $LOGGER.error("Run 'gem install inifile' to install it")
    exit 1
  end
  
  if not repository_dir
    repository_dir = File.expand_path('.')
  end
  repo = HG::Repository.lookup(repository_dir)
  if not repo 
    $LOGGER.error("No Mercurial repository find in \"#{repository_dir}\"")
    exit 1
  end 
  if config then 
    if not repo.xpull_configured? then
      File.open(repo.hgrc(), "a") do | f |
        f.write DEFAULT
      end
    end
    edit(repo.hgrc())
  else
    #repo.xpull()
    repo.xpull_automerge()
  end
end

main()
