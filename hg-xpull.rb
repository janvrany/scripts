#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
A tool to (regularly) pull changes from non-mercurial upstream repository 
into Mercurial repository. This can be used to maintain a fork for code
in Mercurial when the original code (called upstream here) uses some other
version control system. 

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

if not $LOGGER then
  $LOGGER = Logger.new(STDOUT)
  $LOGGER.level = Logger::INFO 
end

$:.push(File.dirname($0))
require 'hglib'

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

module JV
  module Scripts
    class Hg_xpull 

      def configured?()
        return @repo.config.has_section?('xpull')
      end

      def validate_configuration()
        xpull_remote_repo = nil
        xpull_remote_repo_subdir = nil
        xpull_remote_sandbox = nil
        authormap = nil
        branchmap = nil
        splicemap = nil
        xpull_remote_repo_is_cvs = false
        if not @repo.config.has_section?('xpull')
          raise Exception.new("No xpull configured in #{@repo.root}. Run --configure to configure it")
          return
        end
        if not @repo.config['xpull'].has_key?('repository')
          raise Exception.new("No xpull.repository configured for #{@repo.root}")
          return
        end
        xpull_remote_repo = @repo.config['xpull']['repository']      
        xpull_remote_repo_is_cvs = xpull_remote_repo.start_with?(':ext:') || xpull_remote_repo.start_with?(':pserver:')
        if xpull_remote_repo_is_cvs 
          if not @repo.config['xpull'].has_key?('repository-subdir')
            raise Exception.new("No xpull.repository-subdir configured for CVS repository #{xpull_remote_repo}")
            return
          end
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
          validate_configuration()
        rescue => ex
          $LOGGER.error(ex.message)
          return
        end

        xpull_remote_repo = @repo.config['xpull']['repository']
        xpull_remote_repo_is_cvs = xpull_remote_repo.start_with?(':ext:') || xpull_remote_repo.start_with?(':pserver:')
        if xpull_remote_repo_is_cvs 
          xpull_remote_repo_subdir = @repo.config['xpull']['repository-subdir']
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

          if @repo.config.has_section?('xpull-authormap') and not @repo.config['xpull-authormap'].empty?
            authormap = Tempfile.new('authormap')
            $LOGGER.debug("Creating authormap in #{authormap.path}")
            authormap.open
              begin
              for k, v in @repo.config['xpull-authormap']
                $LOGGER.debug("  #{k}=#{v}")
                authormap.write("#{k}=#{v}\n")
              end
            ensure
              authormap.close
            end 
          end

          if @repo.config.has_section?('xpull-branchmap') and not @repo.config['xpull-branchmap'].empty?
            branchmap = Tempfile.new('branchmap')
            $LOGGER.debug("Creating branchmap in #{branchmap.path}")
            branchmap.open
            begin
              for k, v in @repo.config['xpull-branchmap']
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
          cmd  = "hg --config extensions.convert= convert "
          cmd += (authormap ? ' --authors ' + authormap.path : '')
          cmd += (branchmap ? ' --branchmap ' + branchmap.path : '')
          cmd += (splicemap ? ' --splicemap ' + splicemap : '')
          cmd += " #{xpull_remote_sandbox}/#{xpull_remote_repo_subdir} #{@repo.root}"

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

      def run(*args, options)            
        options[:repository] ||= File.expand_path('.')
        options[:config] ||= false
        options[:dryrun] ||= false
        options[:interactive] ||= STDOUT.tty?

        @repo = HG::Repository.lookup(options[:repository])
        if not @repo 
          $LOGGER.error("No Mercurial repository find in \"#{options[:repository]}\"")
          return
        end         
        if options[:config] then 
          if not configured? then
            File.open(@repo.hgrc(), "a") do | f |
              f.write DEFAULT
            end
          end
          edit(@repo.hgrc())
        else
          xpull()    
        end
      end
    end # class hg_xpull
  end # module JV::Scripts    
end # module JV

def opt_parse_key_value(input)
  key, value = input.split('=')
  key.strip!
  value.strip!
  return key, value
end

def run!() 
  opts = {}
  optparser = OptionParser.new do | optparser |
    optparser.banner = "Usage: hg-xull.rb [--cwd DIRECTORY] [options]"
    optparser.on('-C', '--cwd DIRECTORY', "(x)pull changes in repository in DIRECTORY") do | value |
      opts[:repository] = value
    end
    optparser.on(nil, '--dry-run', "Process as normal but do not actually modify repository.") do
      opts[:dryrun] = true
      $DRYRUN = true
    end
    optparser.on(nil, '--debug', "Print debug messages during processing") do
      require 'pry'
      require 'pry-byebug'
      $LOGGER.level = Logger::DEBUG
    end

    optparser.on(nil, '--configure', "Spawns an editor to configure hg-xpull") do
      opts[:config] = true
    end

    optparser.on(nil, '--help', "Prints this message") do
      puts DOCUMENTATION
      puts optparser.help()
      exit 0
    end
  end
  optparser.parse!  

  JV::Scripts::Hg_xpull.new().run(ARGV, opts)  
  
end

run! if __FILE__ == $0
