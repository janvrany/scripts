#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
Rename a Smalltalk/X package.

Renaming Smalltalk/X package is sort of pain as the source code contains a lot
of references to actual package name. WHen package is renamed (or moved to
different subdirectory), all these references has to be updated.

This script makes this task easier by automating some of these changes, namely:

* renames project definition file
* updates package pragma in all source files
* updates package names and paths in makefiles
* updates libInit.cc

This may or may not be sufficient. After running this script, you still should
check for some leftover references (like in readme, documentation, ...) and
update them manually (or fix this script).

Note, that this script does not recurse to nested packages.
Note, that after renaming a package, you must manually:

* update all packages depending in this one
* update build files for all applications depending on this package, directly
  or indirectly.

DOCEND

require 'fileutils'
require 'tmpdir'
require 'optparse'

def error(message, code=1)
  puts "error: #{message}"
  exit code
end

def file_move(oldFile, newFile)

  if oldFile == newFile then
    return
  end

  File.rename(oldFile, newFile)

  oldDir = File.dirname(File.absolute_path(oldFile))
  newDir = File.dirname(File.absolute_path(newFile))

  # Now, if managed by Mercurial, tell it that file has been renamed
  begin
    # Check if one is subdir of the other
    commonDir = nil
    if oldDir.start_with? newDir then
      commonDir = newDir
    elsif newDir.start_with? oldDir then
      commonDir = oldDir
    end
    if commonDir != nil then
      # Search for .hg directory
      d = commonDir
      while ((d != nil) and (not File.directory? (File.join(d, '.hg')))) do
        p = File.dirname(d)
        if p != d then
          d = p
        else
          d = nil
        end
      end
      if d != nil then
        # We have found a Mercurial repository
        `hg rename -A #{oldFile} #{newFile}`
      end
    end
  end
end

def file_edit_replace(file, pattern, replacement)
  contents = File.read(file)
  contents.gsub!(Regexp.new(pattern), replacement)
  File.open(file, "w") {|file| file.puts contents}
end


def rename(oldPkg, newPkg, path = '.')
  puts "info: renaming \#'#{oldPkg}' to \#'#{newPkg}' in #{path}'"

  oldPkgXlatedUnderscores = oldPkg.tr(':/', '_');
  newPkgXlatedUnderscores = newPkg.tr(':/', '_');


  # Validate
  begin
    File.exist?(File.join(path, "#{oldPkgXlatedUnderscores}.st")) || error("Project definition file for #{oldPkg} not found!")
    [ 'Make.spec' , 'Make.proto', 'bc.mak', 'bmake.bat'].each do | file |
      File.exist?(File.join(path, file)) || error("#{file} not found, perhaps #{path} does not contain a Smalltalk/X package?")
    end
  end


  # Pass 1 - update package pragma in all source files
  begin
    Dir.glob(File.join(path , '*.st')) do | each |
      file_edit_replace(each, "'#{oldPkg}'",  "'#{newPkg}'")
    end

    java_extensions = File.join(path, "java", "extensions")
    if File.exist? java_extensions then
      raise Exception.new("Not yet implemented")
    end
  end

  # Pass 2 - rename project definition
  begin
    file_move(File.join(path, "#{oldPkgXlatedUnderscores}.st"), File.join(path, "#{newPkgXlatedUnderscores}.st"))
    file_edit_replace(File.join(path, "#{newPkgXlatedUnderscores}.st"), oldPkgXlatedUnderscores, newPkgXlatedUnderscores)
  end

  # Pass 3 - update libInit.cc
  begin
    oldPkgXlatedEscape = oldPkgXlatedUnderscores.gsub('_', '_137')
    newPkgXlatedEscape = newPkgXlatedUnderscores.gsub('_', '_137')

    libInit_dot_cc = File.join(path, 'libInit.cc')

    file_edit_replace(libInit_dot_cc, "\"#{oldPkg}\"", "\"#{newPkg}\"")
    file_edit_replace(libInit_dot_cc, oldPkgXlatedUnderscores, newPkgXlatedUnderscores)
    file_edit_replace(libInit_dot_cc, oldPkgXlatedEscape, newPkgXlatedEscape)
  end

  # Pass 4 - update package name in makefiles
  begin
    [ 'Make.proto', 'Make.spec', 'bc.mak' ].each do | each |
      file_edit_replace(File.join(path, each), oldPkgXlatedUnderscores, newPkgXlatedUnderscores)
    end

    oldModule, oldPackage = oldPkg.split(':')
    newModule, newPackage = newPkg.split(':')

    file_edit_replace(File.join(path, 'Make.spec'), "MODULE=#{oldModule}", "MODULE=#{newModule}")
    file_edit_replace(File.join(path, 'Make.spec'), "MODULE_DIR=#{oldPackage}", "MODULE_DIR=#{newPackage}")
  end

  # Pass 5 - update TOP in bc.mak & Make.proto
  begin
    oldTOP = (oldPkgXlatedUnderscores.split('_').collect { | e | '..'}).join('/')
    newTOP = (newPkgXlatedUnderscores.split('_').collect { | e | '..'}).join('/')

    file_edit_replace(File.join(path, 'Make.proto'), "TOP=#{oldTOP}/stx", "TOP=#{newTOP}/stx")

    oldTOP = (oldPkgXlatedUnderscores.split('_').collect { | e | '..'}).join("\\")
    newTOP = (newPkgXlatedUnderscores.split('_').collect { | e | '..'}).join("\\")

    file_edit_replace(File.join(path, 'bc.mak'), Regexp.escape("TOP=#{oldTOP}\\stx"), "TOP=#{newTOP}\\stx")
  end

  # Pass 6 - update dependencies in bc.mak & Make.proto
  begin
    oldDepPrefix = "$(INCLUDE_TOP)/#{oldPkg.tr(':', '/')}"
    newDepPrefix = "$(INCLUDE_TOP)/#{newPkg.tr(':', '/')}"

    file_edit_replace(File.join(path, 'Make.proto'), Regexp.escape(oldDepPrefix), newDepPrefix)

    oldDepPrefix = "$(INCLUDE_TOP)\\#{oldPkg.tr(':', '\\')}"
    newDepPrefix = "$(INCLUDE_TOP)\\#{newPkg.tr(':', '\\')}"

    file_edit_replace(File.join(path, 'bc.mak'), Regexp.escape(oldDepPrefix), newDepPrefix)
  end

  # Pass 7 - rename project definition class in extensions.st
  begin
    extensions_dot_st = File.join(path, 'extensions.st')
    if (File.exist? extensions_dot_st) then
      file_edit_replace(extensions_dot_st, oldPkgXlatedUnderscores, newPkgXlatedUnderscores)
    end
  end

  # Pass 8 - rename & update .rc file
  begin
    oldRcFile = "#{oldPkgXlatedUnderscores.split('_').last}.rc"
    newRcFile = "#{newPkgXlatedUnderscores.split('_').last}.rc"

    file_move(oldRcFile, newRcFile)
    file_edit_replace(newRcFile, oldPkgXlatedUnderscores, newPkgXlatedUnderscores)
    file_edit_replace(newRcFile, oldPkg, newPkg)
  end

end


def main()
  old = new = nil

  optparse = OptionParser.new do | opts |
    opts.banner = "Usage: stx-pkg-rename.rb -f|--old OLDNAME -t|--new NEWNAME\n\n"
    opts.on('-f', '--old OLDNAME', "Old (current) package name") do | value |
      old = value
    end

    opts.on('-t', '--new NEWNAME', "New package name") do | value |
      new = value
    end

    opts.on(nil, '--help', "Prints this message") do
      puts DOCUMENTATION
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
