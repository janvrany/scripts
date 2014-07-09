#!/usr/bin/ruby

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

  oldPkgXlatedUnderscores = oldPkg.tr(':/', '_');
  newPkgXlatedUnderscores = newPkg.tr(':/', '_');


  # Pass 1 - update package pragma in all source files
  begin
    Dir.glob(File.join(path , '*.st')) do | each |
      replace(each, "'#{oldPkg}'",  "'#{newPkg}'")
    end

    java_extensions = File.join(path, "java", "extensions")
    if File.exist? java_extensions then
      raise Exception.new("Not yet implemented")
    end
  end

  # Pass 2 - rename project definition
  begin
    File.rename(File.join(path, "#{oldPkgXlatedUnderscores}.st"), File.join(path, "#{newPkgXlatedUnderscores}.st"))
    replace(File.join(path, "#{newPkgXlatedUnderscores}.st"), oldPkgXlatedUnderscores, newPkgXlatedUnderscores)
  end

  # Pass 3 - update libInit.cc
  begin
    oldPkgXlatedEscape = oldPkgXlatedUnderscores.gsub('_', '_137')
    newPkgXlatedEscape = newPkgXlatedUnderscores.gsub('_', '_137')

    libInit_dot_cc = File.join(path, 'libInit.cc')

    replace(libInit_dot_cc, "\"#{oldPkg}\"", "\"#{newPkg}\"")
    replace(libInit_dot_cc, oldPkgXlatedUnderscores, newPkgXlatedUnderscores)
    replace(libInit_dot_cc, oldPkgXlatedEscape, newPkgXlatedEscape)
  end

  # Pass 4 - update package name in makefiles
  begin
    [ 'Make.proto', 'Make.spec', 'bc.mak' ].each do | each |
      replace(File.join(path, each), oldPkgXlatedUnderscores, newPkgXlatedUnderscores)
    end

    oldModule, oldPackage = oldPkg.split(':')
    newModule, newPackage = newPkg.split(':')

    replace(File.join(path, 'Make.spec'), "MODULE=#{oldModule}", "MODULE=#{newModule}")
    replace(File.join(path, 'Make.spec'), "MODULE_DIR=#{oldPackage}", "MODULE_DIR=#{newPackage}")
  end

  # Pass 5 - update TOP in bc.mak & Make.proto
  begin
    oldTOP = (oldPkgXlatedUnderscores.split('_').collect { | e | '..'}).join('/')
    newTOP = (newPkgXlatedUnderscores.split('_').collect { | e | '..'}).join('/')

    replace(File.join(path, 'Make.proto'), "TOP=#{oldTOP}/stx", "TOP=#{newTOP}/stx")

    oldTOP = (oldPkgXlatedUnderscores.split('_').collect { | e | '..'}).join("\\")
    newTOP = (newPkgXlatedUnderscores.split('_').collect { | e | '..'}).join("\\")

    replace(File.join(path, 'bc.mak'), Regexp.escape("TOP=#{oldTOP}\\stx"), "TOP=#{newTOP}\\stx")
  end

  # Pass 6 - update dependencies in bc.mak & Make.proto
  begin
    oldDepPrefix = "$(INCLUDE_TOP)/#{oldPkg.tr(':', '/')}"
    newDepPrefix = "$(INCLUDE_TOP)/#{newPkg.tr(':', '/')}"

    replace(File.join(path, 'Make.proto'), Regexp.escape(oldDepPrefix), newDepPrefix)

    oldDepPrefix = "$(INCLUDE_TOP)\\#{oldPkg.tr(':', '\\')}"
    newDepPrefix = "$(INCLUDE_TOP)\\#{newPkg.tr(':', '\\')}"

    replace(File.join(path, 'bc.mak'), Regexp.escape(oldDepPrefix), newDepPrefix)
  end

  # Pass 7 - rename project definition class in extensions.st
  begin
    extensions_dot_st = File.join(path, 'extensions.st')
    if (File.exist? extensions_dot_st) then
      replace(extensions_dot_st, oldPkgXlatedUnderscores, newPkgXlatedUnderscores)
    end
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
