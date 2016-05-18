# This file is not a standalone script. It is a kind
# of lightweight Mercurial library used by other scripts.

if not $LOGGER then
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
    attr_accessor :root, :config

    def hgrc() 
      return File.join(@root, '.hg', 'hgrc')
    end

    def initialize(directory)
      @root = directory
      config_file = hgrc()
      if File.exist? ( config_file ) 
        $LOGGER.debug("Loading repository config from \"#{config_file}\"")
        @config = HG::config().merge(IniFile.new(:filename => config_file))
      else
        @config = HG::config()
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
    	revs = log(rev)
    	return revs.size > 0      
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
