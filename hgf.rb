#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
Execute command on all repositories in given repository forest [*]. For example,
to execute a pull on all repositories in current directory:

   hgf.rb pull

The command can take any arguments. Command can be either Mercurial internal
command (this means a command that is executed like `hg <command>`) or an
external script.

[*] A repository forest is simply a directory containing many mercurial 
repositories, possibly in nested directories. 

DOCEND

require 'optparse'
require 'fileutils'

include FileUtils

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
require 'hglib'


# List of commands ALWAYS treated as Mercurial commands
# Obtained by
# 
#     hg help | sed -e 's/^ \([a-z-]*\)/"\1", #/g'
#
HG_COMMANDS=[
"add", #           add the specified files on the next commit
"addremove", #     add all new files, delete all missing files
"annotate", #      show changeset information by line for each file
"archive", #       create an unversioned archive of a repository revision
"backout", #       reverse effect of earlier changeset
"bisect", #        subdivision search of changesets
"bookmarks", #     create a new bookmark or list existing bookmarks
"branch", #        set or show the current branch name
"branches", #      list repository named branches
"bundle", #        create a changegroup file
"cat", #           output the current or given revision of files
"clone", #         make a copy of an existing repository
"commit", #        commit the specified files or all outstanding changes
"config", #        show combined config settings from all hgrc files
"copy", #          mark files as copied for the next commit
"diff", #          diff repository (or selected files)
"export", #        dump the header and diffs for one or more changesets
"files", #         list tracked files
"forget", #        forget the specified files on the next commit
"graft", #         copy changes from other branches onto the current branch
"grep", #          search for a pattern in specified files and revisions
"heads", #         show branch heads
"help", #          show help for a given topic or a help overview
"identify", #      identify the working directory or specified revision
"import", #        import an ordered set of patches
"incoming", #      show new changesets found in source
"init", #          create a new repository in the given directory
"log", #           show revision history of entire repository or files
"manifest", #      output the current or given revision of the project manifest
"merge", #         merge another revision into working directory
"outgoing", #      show changesets not found in the destination
"paths", #         show aliases for remote repositories
"phase", #         set or show the current phase name
"pull", #          pull changes from the specified source
"push", #          push changes to the specified destination
"recover", #       roll back an interrupted transaction
"remove", #        remove the specified files on the next commit
"rename", #        rename files; equivalent of copy + remove
"resolve", #       redo merges or set/view the merge status of files
"revert", #        restore files to their checkout state
"root", #          print the root (top) of the current working directory
"serve", #         start stand-alone webserver
"status", #        show changed files in the working directory
"summary", #       summarize working directory state
"tag", #           add one or more tags for the current or given revision
"tags", #          list repository tags
"unbundle", #      apply one or more changegroup files
"update", #        update working directory (or switch revisions)
"verify", #        verify the integrity of the repository
"version", #       output version and copyright information
"convert", #       import revisions from foreign VCS repositories into Mercurial
"crecord", #       text-gui based change selection during commit or qrefresh
"debugshell", #    a python shell with repo, changelog & manifest objects
"evolve", #        extends Mercurial feature related to Changeset Evolution
"hgk", #           browse the repository in a graphical way
"histedit", #      interactive history editing
"mq", #            manage a stack of patches
"purge", #         command to delete untracked files from the working directory
"rebase", #        command to move sets of revisions to a different ancestor
"record", #        commands to interactively select changes for commit/qrefresh
"share", #         share a common history between several working directories
"strip", #         strip changesets and their descendants from history
]

def command?(command)
  hg_command_candidates = HG_COMMANDS.select { | c | c.start_with? command }
  if not hg_command_candidates.empty? then
    if hg_command_candidates.size == 1 then
      return false
    else
      puts "hgf: command '#{command}' is ambiguous:"      
      hg_command_candidates.each { | c | puts "     #{c}"}
      exit 1
    end
  end

  if File.exist? command then
    return true
  else
    ENV['PATH'].split(':').each do | directory |
      if File.exist? File.join(directory, command)
        return true
      end
    end
  end
  return false
end

def execute(command, repo_path, print_prefix)
  if not print_prefix then
    system *command
  else
    require 'open3'
    stdout, stderr, status = Open3.capture3(*command)
    stdout.split().each do | line |
      puts "#{repo_path}: #{line}\n"
    end
    stderr.split().each do | line |
      puts "#{repo_path}: #{line}\n"
    end
  end
end

def run!
  root_dir = '.'
  print = false
  banner = false
  prefix = false
  optparse = OptionParser.new do | opts |
    opts.banner = "Usage: #{$0} [--cwd DIRECTORY] [--print|--banner] -- COMMAND [ARG1 [ARG2 [...]]]"
    opts.on('-C', '--cwd DIRECTORY', "Enumerate repositories under DIRECTORY") do | value |
      root_dir = value
    end
    opts.on('-p', '--print', "Print paths to repositories rather than executing command ") do
      print = true
    end
    opts.on('-b', '--banner', "Print 'banner' before each output to separate outputs for individual repos") do
      banner = true
    end
    opts.on('-B', '--prefix', "Prefix each line of output with repository path (useful for piping output to `grep`)") do
      prefix = true
    end
    opts.on(nil, '--help', "Prints this message") do
      puts DOCUMENTATION
      puts optparse.help()
      exit 0
    end
  end
  optparse.parse!

  if not File.exist? root_dir then
    puts "No such directory: #{root_dir}"
    exit 1
  end
  if not File.directory? root_dir then
    puts "Not a directory: #{root_dir}"
    exit 2
  end
  HG::forest(root_dir) do | repo |
    begin
      if print
        puts repo.path
      end
      if ARGV.size > 0 then
        if banner
          puts "== #{repo.path} =="
        end
        if command? ARGV[0]
          FileUtils.chdir repo.path do
            execute(ARGV, repo.path, prefix)
          end
        else
          execute(['hg' , '--cwd' , repo.path] + ARGV, repo.path, prefix)
        end
        if banner
          puts "\n"
        end
      else
        if not print then
          puts "No command given"
          exit 3
        end
      end
    rescue Interrupt
      # Interrupted
    end
  end
end

run! if __FILE__ == $0
