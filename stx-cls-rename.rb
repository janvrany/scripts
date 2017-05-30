#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
Rename a class in Smalltalk/X package.

This script renames a class at file level. It's better to do this from IDE
and then commit from IDE. Use only if you know what are you doing. 

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
  begin
    oldContents = File.read(file).encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '?')
    newContents = oldContents.gsub(Regexp.new(pattern), replacement)
    if (oldContents != newContents)
      File.open(file, "w") {|file| file.puts newContents}
    end
  rescue Exception => e  
    error("Failed to edit file #{file}: #{e.message}")
  end
end


def rename(oldCls, newCls, path = '.')
  puts "info: renaming \#'#{oldCls}' to \#'#{newCls}' in #{path}'"

  oldClsXlatedUnderscores = oldCls.tr(':', '_');
  newClsXlatedUnderscores = newCls.tr(':', '_');

  # Validate
  begin
    File.exist?(File.join(path, "#{oldClsXlatedUnderscores}.st")) || error("Class container '#{oldCls}.st not found!")
    [ 'Make.spec' , 'Make.proto', 'bc.mak', 'bmake.bat'].each do | file |
      File.exist?(File.join(path, file)) || error("#{file} not found, perhaps #{path} does not contain a Smalltalk/X package?")
    end
  end


  # Pass 1 - update class name in all .st files
  begin
    Dir.glob(File.join(path , '*.st')) do | each |
      file_edit_replace(each, "'#{oldCls}'",  "'#{newCls}'")
    end

    java_extensions = File.join(path, "java", "extensions")
    if File.exist? java_extensions then
      raise Exception.new("Not yet implemented")
    end
  end

  # Pass 2 - rename project definition
  begin
    file_move(File.join(path, "#{oldClsXlatedUnderscores}.st"), File.join(path, "#{newClsXlatedUnderscores}.st"))
    file_edit_replace(File.join(path, "#{newClsXlatedUnderscores}.st"), oldClsXlatedUnderscores, newClsXlatedUnderscores)
  end

  # Pass 3 - update libInit.cc
  begin
    libInit_dot_cc = File.join(path, 'libInit.cc')
    file_edit_replace(libInit_dot_cc, oldClsXlatedUnderscores, newClsXlatedUnderscores)
  end

  # Pass 4 - update package name in makefiles
  begin
    [ 'Make.proto', 'Make.spec', 'bc.mak' ].each do | each |
      file_edit_replace(File.join(path, each), oldClsXlatedUnderscores, newClsXlatedUnderscores)
    end

  end

  # Pass 9 - update abbrev stc
  begin
    file_edit_replace(File.join(path, 'abbrev.stc'), oldCls,  newCls)
  end


end


def main()
  old = new = nil

  optparse = OptionParser.new do | opts |
    opts.banner = "Usage: stx-cls-rename.rb -f|--old OLDNAME -t|--new NEWNAME\n\n"
    opts.on('-f', '--old OLDNAME', "Old (current) class name") do | value |
      old = value
    end

    opts.on('-t', '--new NEWNAME', "New class name") do | value |
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
    puts "error: no old class name specified"
    puts optparse.help()
    exit 0
  end

  if new == nil then
    puts "error: no new class name specified"
    puts optparse.help()
    exit 0
  end

  rename(old, new, '.')
end

main()
