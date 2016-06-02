# This file is not a standalone script. It is a kind
# of lightweight Mercurial library used by other scripts.

if not $LOGGER then
  require 'logger'
  $LOGGER = Logger.new(STDOUT)
  $LOGGER.level = Logger::INFO  
end

begin
  require 'inifile'
rescue LoadError => ex
  $LOGGER.error("Cannot load package 'inifile'")
  $LOGGER.error("Run 'gem install inifile' to install it")
  exit 1
end

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

module HG
  @@config = nil

  def self.hg()
  	raise Exception.new("Not yet implemented")
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

    def log(revset, template = "{node|short}")
      out , success = syso "hg --cwd #{@path} log --rev \"#{revset}\" --template \"#{template}\\n\"" 
      if success
        return out.split("\n")
      else
        return []
      end
    end

    def pull(remote = 'default')
      if not sys "hg --cwd #{@path} pull #{remote}" then
        raise Exception.new("Failed to pull from #{remote}")
      end
    end

    def push(remote = 'default')
      if not sys "hg --cwd #{@path} push #{remote}" then
        raise Exception.new("Failed to push to #{remote}")
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
      if not sys "hg --config extensions.share= share -U -B #{@path} #{dst}"
        raise Exception.new("Failed to make shared clone of #{@path}")
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
      if not sys "hg --cwd #{@path} update -r #{rev}" then
        raise Exception.new("Failed to update working copy to revision '#{rev}'")
      end
    end

    # Merge given revision. Return true, if the merge was
    # successful, false otherwise
    def merge(rev)
      if not has_revision? rev then
        raise Exception.new("Revision #{rev} does not exist")
      end
      return sys "hg --cwd #{@path} merge #{rev}"
    end

    def commit(message)
      user_arg = ''
      if not @config['ui'].has_key? 'username' then
        user_arg = "--user 'Merge Script"
      end
      if not sys "hg --cwd #{@path} commit -m '#{message}' #{user_arg}" then
        raise Exception.new("Failed to commit")
      end
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
      if not sys "hg init #{directory}" then
        raise Exception.new("Failed to initialize repository in #{directory}")
      end
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
