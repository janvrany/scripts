#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
Create and/or edit Bee Smalltalk configuration file. 



If no -u nor -l option is given, edits user config file (~/.bee.ini)

DOCEND

# Contents of default config file
DEFAULT = <<DEFEND
[wine]
# Configures the WINE prefix to use when running Bee Smalltalk,
# "prefix" is a "configuration directory" or "bottle" (former WINE term). 
# It's strongly reccomended to use separate WINE prefix for Bee Smalltalk
# prefix = ~/.bee-wine

# Configures path to 'wine' executable to use. If not set, the default
# `wine` found along PATH is used. 
# loader = /usr/src/wine/wine

DEFEND

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


def main()
  file = '~/.bee.ini'
  winecfg = false;
  
  optparse = OptionParser.new do | opts |
    opts.banner = "Usage: bee-config.rb [-u | -l] \n\n"

    opts.on('-u', '--user', "Edit user config file (~/.bee.ini). The file is created if it does not exist.") do | value |
      file = '~/.bee.ini'
    end

    opts.on('-l', '--local', "Edit local config file (bee.ini). The file is created if it does not exist.") do | value |
      file = 'bee.ini'
    end

    opts.on(nil, '--help', "Prints this message") do
      puts DOCUMENTATION
      puts optparse.help()
      exit 0
    end
  end

  optparse.parse!

  file = File.expand_path(file)
  if not File.exist? file
  	File.open(file, "w") do | f |
      f.write DEFAULT
    end
  end

  editors = [
    ENV['EDITOR'],
    "sensible-editor",
    "nano",
    "vim",
    "notepad.exe"
  ]
  editors.each do | editor |
    if editor 
      if system "#{editor} #{file}"
        exit 0;
      end
    end
  end
  error("No suitable editor found, please define EDITOR environment variable");
end

main()
