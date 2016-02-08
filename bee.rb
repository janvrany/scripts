#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
Run Bee Smalltalk under WINE

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

def config() 
  if $CONFIG == nil then
    begin
      require 'inifile'
    rescue LoadError => ex
      error "Could load 'inifile'. Run 'gem install inifile' to install it."
    end
    files = [ File.expand_path('~/.bee.ini') ]      
    $CONFIG = IniFile.new()
    files.each do | file |
      if File.exist?(file)                  
        $CONFIG.merge!(IniFile.new(:filename => file))
      end
    end  
  end
  return $CONFIG
end


def main()
  prefix = nil
  loader = nil
  winecfg = false
  
  optparse = OptionParser.new do | opts |
    opts.banner = "Usage: bee.rb [-p PREFIX] [-l LOADER]\n\n"

    opts.on('-p', '--wine-prefix PREFIX', "Run Bee using given WINE prefix. Same as --config wine.prefix=PREFIX") do | value |
      prefix = value
    end

    opts.on('-l', '--wine-loader LOADER', "Run Bee using given WINE loader. Same as --config wine.loader=LOADER") do | value |
      loader = value
    end

    opts.on('-D', '--config SECTION.KEY=VALUE', "Override configuration KEY in SECTION with VALUE") do | value |
      section, key, value = 'SECTION.KEY='.scan(/(.+)\.(.+)=(.*)/)[0]
      config[section][key] = value
    end

    opts.on('--winecfg', "Runs winecfg (instead of Bee Smalltalk)") do | value |
      winecfg = true;
    end


    opts.on(nil, '--help', "Prints this message") do
      puts DOCUMENTATION
      puts optparse.help()
      exit 0
    end
  end

  optparse.parse!

  if not prefix then
    prefix = config['wine']['prefix']
  end

  if not loader then
    loader = config['wine']['loader']
  end

  if prefix and (not prefix.empty?) then
    ENV['WINEPREFIX'] = File.expand_path(prefix)
  end

  if loader and (not loader.empty?) then
    ENV['WINELOADER'] = loader
  end

  if winecfg then
  	if loader then 
  		bin_fir = File.dirname(loader)
  		if File.exist? "#{bin_fir}/winecfg" then
  			exec("#{bin_fir}/winecfg")  	
  		end
  	end
  	exec("winecfg")  	  	
  else
  	# Find BeeDev.exe
  	if File.exist? "BeeDev.exe" 
  		exec("#{loader || 'wine'} BeeDev.exe")  
  	else
  		error("Could not find DeeDev.exe in working directory")
    end
  end
end

main()
