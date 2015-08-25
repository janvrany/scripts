#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
Set a package in Bee changeset (.ch)

For all changes in given Bee changeset file which doesn't have a project
set, set it to given one. If -f or --force is specified, then overwrite
package even for changes which do have package set. 
DOCEND

require 'fileutils'
require 'optparse'
require 'pp'

def error(message, code=1)
  puts "error: #{message}"
  exit code
end

def pause(msg = "Press enter key to continue (CTRL-C to abort)")
  puts msg
  ignored = STDIN.gets
end

def file_edit_replace(file, patterns_and_replacements, inplace = false)
  contents = File.read(file)
  patterns_and_replacements.each do | pattern_and_replacement |  
    contents.gsub!(pattern_and_replacement[0], pattern_and_replacement[1])
  end
  if inplace then
    File.open(file, "w") {|file| file.puts contents}
  else
    STDOUT.puts contents
  end
end

def main()
  packagename = nil
  inplace = false
  force = false

  optparse = OptionParser.new do | opts |
    opts.banner = "Usage: bee-pkg-set.rb -p|--package PACKAGENAME [FILE1 [FILE2 [...]]]\n\n"
    opts.on('-p', '--package PACKAGENAME', "Package name to set in given files") do | value |
      packagename = value
    end

    opts.on('-i', '--inplace', "Modify changeset file in place, i.e., save modified changset back to the file. Similar to sed's -i option. Default is NOT to modify in place.") do | value |
      packagename = true
    end

    opts.on('-f', '--force', "Enforce package even for changes that have package already set. Default is OFF") do | value |
      force = true
    end

    opts.on(nil, '--help', "Prints this message") do
      puts DOCUMENTATION
      puts optparse.help()
      exit 0
    end
  end

  optparse.parse!

  if packagename == nil then
    puts "error: no package name specified (use -p)"
    puts optparse.help()
    exit 0
  end

  ARGV.each do | file |
    if not File.exist? file then
      error("file does not exist: #{file}")
    end
  end

  edits = [          
    [ %r{category: #('[^']*')\!} ,     "category: \#\\1 project: '#{packagename}'!" ],
    [ %r{category: #([[:alnum:]]*)\!} ,     "category: \#\\1 project: '#{packagename}'!" ],
    [ %r{className: '([[:alnum:]]*)'\!} ,    "className: '\\1' project: '#{packagename}'!" ],    
  ]
  
  if force then
    edits << [ %r{project: '.*'\!}   ,      "project: '#{packagename}'!" ]
  end

  ARGV.each do | file |    
    file_edit_replace(file, edits, inplace)
  end
end

main()
