#!/usr/bin/ruby
#
require 'fileutils'
require 'tmpdir'
require 'optparse'

def replace(file, pattern, replacement)
  contents = File.read(file)
  contents.gsub!(Regexp.new(pattern), replacement)
  File.open(file, "w") {|file| file.puts contents}
end


def rename(oldPkg, newPkg, path = '.')
  puts "Renaming \#'#{oldPkg}' to \#'#{newPkg}' in #{path}'"


  # Pass 1 - update package pragma in all source files
  begin
    Dir.glob(File.join(path , '*.st')) do | each |
      replace(each, "'#{oldPkg}'",  "'#{newPkg}'")
    end
  end

  # Pass 2 - rename project definition file
  begin
    oldPkgDefName = oldPkg.tr(':/', '_');
    newPkgDefName = newPkg.tr(':/', '_');
    File.rename(File.join(path, "#{oldPkgDefName}.st"), File.join(path, "#{newPkgDefName}.st"))

    replace(File.join(path, "#{newPkgDefName}.st"), oldPkgDefName, newPkgDefName)
  end

  # Pass 3 - update libInit.cc
  begin
    oldPkgXlated1 = oldPkg.tr(':/', '_');
    newPkgXlated1 = newPkg.tr(':/', '_');

    oldPkgXlated2 = oldPkgXlated1.gsub('_', '_137')
    newPkgXlated2 = newPkgXlated1.gsub('_', '_137')

    libInit_dot_cc = File.join(path, 'libInit.cc')

    replace(libInit_dot_cc, "\"#{oldPkg}\"", "\"#{newPkg}\"")
    replace(libInit_dot_cc, oldPkgXlated1, newPkgXlated1)
    replace(libInit_dot_cc, oldPkgXlated2, newPkgXlated2)
  end

  # Pass 4 - update makefiles
  begin
    oldPkgXlated = oldPkg.tr(':/', '_');
    newPkgXlated = newPkg.tr(':/', '_');

    [ 'Make.proto', 'Make.spec', 'bc.mak' ].each do | each |
      replace(File.join(path, each), oldPkgXlated, newPkgXlated)
    end

    oldModule, oldPackage = oldPkg.split(':')
    newModule, newPackage = newPkg.split(':')

    replace(File.join(path, 'Make.spec'), "MODULE=#{oldModule}", "MODULE=#{newModule}")
    replace(File.join(path, 'Make.spec'), "MODULE_DIR=#{oldPackage}", "MODULE_DIR=#{newPackage}")
  end

end


def main()
  old = new = nil

  optparse = OptionParser.new do | opts |
    opts.banner = "Usage: stx-pkg-rename.rb -f|--old OLDNAME -t|--new NEWNAME"
    opts.on('-f', '--old OLDNAME', "Old (current) package name") do | value |
      old = value
    end

    opts.on('-t', '--new NEWNAME', "New package name") do | value |
      new = value
    end

    opts.on(nil, '--help', "Prints this message") do
      puts optparse.help()
      exit 0
    end
  end

  optparse.parse!

  if old == nil then
    puts "error: no old package name specified"
    puts optparse.help()
    exit 0
  end

  if new == nil then
    puts "error: no new package name specified"
    puts optparse.help()
    exit 0
  end

  rename(old, new, '.')
end

main()
