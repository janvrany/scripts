#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND

Script to examine CVS working copy, `cvs add` all new files and
`cvs remove` all missing files.

This comes handy when (automagically) transplating changes from one SCM to
CVS.

DOCEND

#DEBUG=true
DEBUG=false

require 'fileutils'
require 'tmpdir'
require 'optparse'

include FileUtils

def error(message, code=1)
  puts "error: #{message}"
  raise Exception.new("Explode")
  exit code
end

def pause(msg = "Press enter key to continue (CTRL-C to abort)")
  puts msg
  ignored = STDIN.gets
end

def execute(command, files = [])
  cmd = "#{command} #{files.collect { | e | "'#{e}'" }.join(' ')}"
  if not DEBUG then
    out = `#{cmd}`
    if not $?.success? then
      puts "error: "
      puts out
      puts "^ command output ^"
      error("failed to execute: '#{cmd}' status: #{$?.exitstatus}")
    end
  else
    puts "DEBUG: executing '#{cmd}'"
  end
end

public

def cvs_ignore_file?(file, ignore = [])
  if ['CVS', '.hg' , '.', '..', 'README.CVS'].include?(file) then
    return true
  end
  # Builtin patterns...
  ['*.H', '*.o', '*~', '*.STH', '*.so'].each do | pattern |
    if File.fnmatch(pattern, file) then
      return true;
    end
  end
  ignore.each do | pattern |
    if File.fnmatch(pattern, file) then
      return true;
    end
  end
  return false
end

def cvs_for_each(root, ignore = [])
  cvs_ignore_file = File.join(root, '.cvsignore')
  cvs_ignore_list = ignore
  if File.exist? cvs_ignore_file then
    cvs_ignore_list = cvs_ignore_list.clone
    File.open(cvs_ignore_file).each do | pattern |
      cvs_ignore_list << pattern
    end
  end
  Dir.new(root).each do | file |
    if not ['CVS', '.hg' , '.', '..', 'README.CVS'].include?(file)
      if not cvs_ignore_file?(file, ignore) then
        yield File.join(root, file)
      end
    end
  end
end


def cvs_entries(directory)
  entries_file = File.join(directory, 'CVS', 'Entries')
  if File.exist?(entries_file) then
    entries = []
    File.open(entries_file).each do | line |
      file = line.split('/')[1]
      entries << file if file != nil
    end
    entries_log_file = File.join(directory, 'CVS', 'Entries.Log')
    if File.exist?(entries_log_file) then
      File.open(entries_log_file).each do | line |
        if (line[0] == 'A') then
          file = line.split('/')[1]
          entries << file if file != nil
        end
      end
    end
    return entries
  else
    return nil
  end
end

def cvs_add_directory(directory, ignore = [])
  if (File.directory? directory) then
    add = []
    cvs_for_each(directory, ignore) do | file |
      add << file
    end
    cvs_add_all(add, ignore)
  end
end

def cvs_add_all(files, ignore = [])
  return if files.size == 0
  puts "Adding: "
  files.each { | e | puts "    #{e}" }
  execute("cvs add", files)
  files.each do | file |
    if File.directory? file then
      cvs_add_directory(file)
    end
  end
end


def cvs_remove_all(files, ignore = [])
  return if files.size == 0
  files.each do | file |
    if File.directory?(file) then
      cvs_remove_directory(file)
    else
      execute("rm -f #{file}")
    end
  end
  puts "Removing: "
  files.each { | e | puts "    #{e}" }
  execute("cvs remove", files)
end

def cvs_remove_directory(directory)
  entries = cvs_entries(directory)
  return if entries == nil
  remove = []
  entries.each do | entry |
    file = File.join(directory, entry)
    if File.exist?(file) then
      remove << file
    end
  end
  cvs_remove_all(remove)
end



def cvs_add_remove(root, ignore = [])
  entries = cvs_entries(root)
  if entries == nil then
    cvs_add_all( [root] )
    return
  end

  to_add = []
  to_remove = entries.collect { | e | File.join(root, e) }

  cvs_for_each(root, ignore) do | file |
    name = File.basename(file)
    if entries.include?(name) then
      to_remove.delete(file)
      if File.directory?(file) then
        cvs_add_remove(file, ignore)
      end
    else
      if not cvs_ignore_file?(file, ignore) then
        if File.directory?(File.join(file, 'CVS')) then
          cvs_add_remove(file, ignore)
        else
          to_add << file
        end
      end
    end
  end

  cvs_add_all(to_add, ignore)
  cvs_remove_all(to_remove, ignore)
end

def cvs_add_remove_main()
    root = '.'

    optparse = OptionParser.new do | opts |
      opts.banner = "Usage: cvs-addremove.rb [-C DIR]"
        opts.on('-C', "--chdir DIRECTORT", "Examine DIRECTORT instead of current working directory (default)") do | s |
            root = s
        end
        #opts.on('-i', '--interactive', "Stop after each successfuly applied patch, waiting for user to confirm.") do
            interactive = true
        #end
        opts.on(nil, '--help', "Prints this message") do
            puts DOCUMENTATION
            puts optparse.help()
            exit 0
        end
    end
    optparse.parse!

    if not File.exist? root then
      error("specified directory does not exist!")
    elsif not File.directory? root then
      error("specified directory is not directory")
    elsif not File.directory?(File.join(root, 'CVS')) then
      error("Source directory is not a CVS working copy")
    end

    Dir.chdir root do
      cvs_add_remove(".")
    end
end

if __FILE__ == $0 then
  cvs_add_remove_main()
end

