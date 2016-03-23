#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
Extract #define'd constants from C header files and prints Bee expressions
that initialize pool dictionary. 

This script requires `coan` to be installed. 

Caveats: 
   
The value parser/converter is rathe simple, i.e., it does not parse
value as expression, it merely does regexp replaces. Therefore for
#defines that define macros to call functions, cast value and so on,
resulting Smalltalk expression would be invalid. 

Therefore it is necessary to manually clean up the result. 

Example:

To extract #defines for ODBC, execute:

   ./bee-extract-c-defines.rb /usr/include/sql.h /usr/include/sqlext.h

Note, that you should cleanup the result

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

C_2_ST_SIMPLE_EDITS = [
  # Simple numbers
  [ %r{0x([0-9A-Fa-f]+)U?L?} ,     "16r\\1" ],
  [ %r{0x([0-9]+)U?L?} ,           "\\1" ],

  # Simple strings
  [ %r{^"([^"]+)"} ,              "'\\1'" ],

]


def c_2_st(value, poolname, defined_so_far) 
  C_2_ST_SIMPLE_EDITS.each do | pattern_and_replacement |  
    value.gsub!(pattern_and_replacement[0], pattern_and_replacement[1])
  end
  defined_so_far.each do | name |
    replacement = "(#{poolname} at: '#{name}')"
    if value == name then
      value = replacement
    else      
      value.gsub!(/([^A-Za-z_])#{name}([^A-Za-z_0-9])/, "\\1#{replacement}\\2")      
    end
  end
  return value
end

def process_line(line, poolname, defined_so_far)  
  match = /\#define\s+([A-Z_][A-Z0-9_]+)\s+(.*)/.match(line)
  if match then
    captures = match.captures
    if not captures.empty? and not captures[1].empty?
      name = captures[0]
      value = c_2_st(captures[1], poolname, defined_so_far)
      if value 
        puts "\t\t\"#{line.chop.gsub(/\"/, "'")}\""
        puts "\t\tat: '#{name}' put: #{value};"                
        puts
        if not defined_so_far.include? name then
          defined_so_far.push(name)
        end
      end
    end
  end
end


def file_edit_replace(file, patterns_and_replacements)
  contents = File.read(file)
  patterns_and_replacements.each do | pattern_and_replacement |  
    contents.gsub!(pattern_and_replacement[0], pattern_and_replacement[1])
  end
  STDOUT.puts contents
end

def main()
  coan = nil
  poolname = nil
  optparse = OptionParser.new do | opts |
    opts.banner = "Usage: bee-extract-c-defines.rb [FILE1 [FILE2 [...]]]\n\n"

    opts.on('-c', '--coan PATH', "Path to `coan` binary") do | value |      
      coan = value
    end

    opts.on('-p', '--pool NAME', 'Name of the pool in which to define values') do | value |
      poolname = value
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

  if coan == nil then
    coan = '/usr/bin/coan'
    if not File.exist? coan then
      coan = '/usr/local/bin/coan'
      if not File.exist? coan then
        coan = '/usr/src/coan-6.0.1/src/coan'
      end
    end
    if not File.exist? coan then
      error("Could not find `coan` binary (tried /usr/bin/coan, /usr/local/bin/coan, /usr/src/coan-6.0.1/src/coan")
    end
  else
    if not File.exist? coan
      error("#{coan} does not exist")
    end
  end

  if not poolname then
    error("No pool name specified. Use --pool to specify it")
  end


  IO.popen(["#{coan}" , 'defs'] + ARGV, :err=>[:child, :out]) do | out |
    defined_so_far = []
    puts "initializeConstants"
    puts "\t#{poolname}"
    out.readlines.each do | line |
      process_line(line, poolname, defined_so_far)
    end
    puts "\t\tyourself."
  end

end

main()
