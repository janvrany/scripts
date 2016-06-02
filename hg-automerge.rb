#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
Simple script to automate merging from one branch to another. The source
branch and merge-into branch are configured in repository's `.hg/hgrc`. 
Run 

    hg-automerge.rb --config 

to configure it. 

## Integration with Mercurial

Add following aliases to your "$HOME/.hgrc"

    [alias]
    am=!hg-automerge.rb "$@"

Then you'd be able to run xpull simply as any other Mercurial command: 

    hg am

(Note, that the above assumes that hg-automerge.rb is in your PATH. If not,
then use full path to the hg-automerge.rb file)

DOCEND

# Contents of default configuration sections
DEFAULT = <<DEFEND
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

if not $LOGGER then
  $LOGGER = Logger.new(STDOUT)
  $LOGGER.level = Logger::INFO  
end

$:.push(File.dirname($0))
require 'hglib'

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

def confirm(message, default, interactive = STDOUT.tty?)  
  return default if not interactive 
  STDOUT.write "#{message} (#{default ? 'Y' : 'y'}/#{default ? 'n' : 'N'})? "
  while true do
    answer = gets.chop
    return default if answer == ''
    if ['y', 'Y', 'yes', 'YES', 'Yes', 'true', 'True'].include? answer then
      return true
    end
    if ['n', 'N', 'no', 'NO', 'No', 'false', 'False'].include? answer then
      return false
    end
    STDOUT.write "Invalid answer, please answer either 'y' or 'n': "
  end
end

module JV
  module Scripts
    class Hg_automerge
      def automergerc() 
        return File.join(@repo.path, '.hgautomerge') 	
      end

      def configured?()
        if not @repo.config['automerge'].has_key?('automerge') then
          config_file = automergerc()
          if File.exist? ( config_file ) 
            $LOGGER.debug("Loading automerge config from \"#{config_file}\"")
            @repo.config = @repo.config.merge(IniFile.new(:filename => config_file))      
          end
        end
        return @repo.config['automerge'].has_key?('automerge')
      end

      def run(*args, options)            
        options[:repository] ||= File.expand_path('.')
        options[:config] ||= false
        options[:interactive] ||= STDOUT.tty?
        
        @repo = HG::Repository.lookup(options[:repository])
        if not @repo 
          $LOGGER.error("No Mercurial repository find in \"#{options[:repository]}\"")
          exit 1
        end 
        if options[:config]then 
          if not configured? then
            File.open(automergerc(), "a") do | f |
              f.write DEFAULT
            end
          end
          edit(automergerc())
          return
        else
          if not configured? then
            $LOGGER.info "hg-automerge not configured for #{@repo.path}"
            $LOGGER.info "run '#{$0} --config' to configure it."
            return      
          end
          from_branch, into_branch = @repo.config['automerge']['automerge'].split(':')
          if from_branch == nil then 
            $LOGGER.warn("from_branch is nil")
            return
          end
          if not @repo.has_revision?(from_branch) then
            $LOGGER.warn("hg-automerge: from branch \"#{from_branch}\" does not exit")
            return
          end
          if into_branch == nil then 
            $LOGGER.warn("hg-automerge: into_branch is nil")
            return
          end
          if not @repo.has_revision?(into_branch) then
            $LOGGER.warn("hg-automerge: info branch \"#{into_branch}\" does not exit")
            return
          end

          into_branch_revs = @repo.log(into_branch)
          if into_branch_revs.size > 1 then
            $LOGGER.error "Multiple revisions for '#{into_branch}'. Must merge manually."
            return
          end

          from_branch_revs = @repo.log(from_branch)
          if from_branch_revs.size > 1 then
            $LOGGER.error "Multiple revisions for '#{from_branch}'. Must merge manually."
            return
          end

          repo_rev = @repo.log('.')[0]
          
          if not @repo.has_revision? "head() and branch(#{from_branch}) and not ancestors(#{into_branch}) and not secret()"
            $LOGGER.info "Nothing to merge"      
            return
          end  

          merge_wc_dir = nil
          merge_wc = @repo
          begin
            begin
              if repo_rev != into_branch_revs[0] then
                binding.pry
                $LOGGER.debug "Creating temporary clone in #{merge_wc_dir}"
                merge_wc_dir = Dir.mktmpdir()
                merge_wc = @repo.share("#{merge_wc_dir}/x");
                merge_wc.update(into_branch);
              end
              if $LOGGER.debug? then
                from_branch_rev = from_branch_revs[0]
                into_branch_rev = into_branch_revs[0]
                $LOGGER.debug "Merging '#{from_branch}' (from_branch_rev) into #{into_branch} (#{into_branch_rev})"
              end
              if merge_wc.merge(from_branch) then
                $LOGGER.debug "Merge succeeded"
                if confirm("Merge succeeded, commit?", true, options[:interactive])  
                  $LOGGER.debug "Commiting"
                  merge_wc.commit("Merge");
                end
              else
                $LOGGER.warning "Merge failed"
              end
            rescue ex
              $LOGGER.error "error when merging: #{ex.description}"
            end
          ensure
            if merge_wc_dir then
              $LOGGER.debug "Cleaning temporary clone in #{merge_wc_dir}" 
              rm_rf merge_wc_dir 
            end
          end
        end
      end    
    end # class hg_automerge
  end # module JV::Scripts    
end # module JV

def run!() 
  opts = {}
  optparser = OptionParser.new do | optparser |
    optparser.banner = "Usage: $0 [--cwd REPOSITORY] [options]"
    optparser.on('-C', '--cwd REPOSITORY', "automerge REPOSITORY") do | value |
      opts[:repository] = value
    end
    optparser.on(nil, '--dry-run', "Process as normal but do not actually modify repository. Implies --verbose") do
      $DRYRUN = true
      if ($LOGGER.level > Logger::INFO) 
        $LOGGER.level = Logger::INFO
      end
    end

    optparser.on(nil, '--non-interactive', "Run in non-interactive mode. Default is true if run from an interactive session, false otherwise.") do 
      OPTIONS[:interactive] = false
    end      

    optparser.on(nil, '--verbose', "Print more information during processing") do
      if ($LOGGER.level > Logger::INFO) 
      $LOGGER.level = Logger::INFO
      end
    end
    optparser.on(nil, '--debug', "Print debug messages during processing") do
      $LOGGER.level = Logger::DEBUG
      begin
        require 'pry'
        require 'pry-byebug'
      rescue LoadError => ex
        $LOGGER.info "Gems pry and/or pry-byebug not installed, no interactive debugging available"
        $LOGGER.info "Run 'gem install pry pry-byebug' to install."
      end      
    end

    optparser.on(nil, '--config', "Spawns an editor to configure hg-automerge") do
      opts[:config] = true
    end

    optparser.on(nil, '--help', "Prints this message") do
      puts DOCUMENTATION
      puts optparse.help()
      exit 0
    end
  end
  optparser.parse! 

  JV::Scripts::Hg_automerge.new().run(ARGV, opts)
end

run! if __FILE__ == $0
