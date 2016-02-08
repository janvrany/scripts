#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
Normalizes a SmalltalkX VM trace log so it can be compared using diff

Namely it: 

* replaces all pointers (memory addresses) with 0xXXXXXXXX


Currently supported trace log is output of -Tjexec. More will come. 
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
    opts.banner = "Usage: stx-normalize-trace-log.rb [FILE1 [FILE2 [...]]]\n\n"

    opts.on('-i', '--inplace', "Modify log file in place, i.e., save modified log back to the file. Similar to sed's -i option. Default is NOT to modify in place.") do | value |
      inplace = true
    end

    opts.on(nil, '--help', "Prints this message") do
      puts DOCUMENTATION
      puts optparse.help()
      exit 0
    end
  end

  optparse.parse!

  ARGV.each do | file |
    if not File.exist? file then
      error("file does not exist: #{file}")
    end
  end

  edits = [          
    # Pointers
    [ %r{0x\h+([ \]])} ,     "0xXXXXXXXX\\1" ],    # 32bit addresses
    [ %r{0x\h+([ \]])} ,     "0xXXXXXXXX\\1" ],    # 64bit addresses   

    # Number of scavenges and/or process ID's may not match, strip them off
    [ %r{scaveneges=\d+ pid=\d+ l=\d+}, ""],
    [ %r{scaveneges=\d+ pid=\d+}, ""],
    [ %r{INT\/LONG},	     "int/long" ],

    [ %r{\(0x016-?\h+\)$}, "" ],    

    # Source warnings - these are just annoying...
    [ %r{^Class \[info\].*\n},""],                 
    [ %r{^Class \[warning\].*\n},""],
    [ %r{^SourceCodeManager \[info\].*\n},""]
  ]
  

  ARGV.each do | file |    
    file_edit_replace(file, edits, inplace)
  end
end

main()
