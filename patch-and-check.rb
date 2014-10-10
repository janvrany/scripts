#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
A simple script to apply a sequence of .patch files and after each,
check if it applied cleanly.

Useful when you have two eventually divegring lines of development in two
different SCMs and want to transpant fixes done in one line on top of a
head in the other (such as transplating changes from HG to on top of CVS HEAD)

The check script (if provided) is passed a path to working directory and must
return exit status 0 if working copy is good of nonzero if its bad.

There's two "built-in" check scripts:

  * "internal:make" (the default, if no check script is used) which just runs
     a make. A patch is consireded good if make proceeds without errors.
  * "internal:none" a patch is slways consireded good (as long as patching
     proceeds fine)

See also:

* hg export
* hg import

DOCEND

require 'fileutils'
require 'tmpdir'
require 'optparse'

include FileUtils
$DIR_WORK = '.'

def error(message, code=1)
  puts "error: #{message}"
  exit code
end

def check(check_script, dir = $DIR_WORK)
    if check_script == 'internal:none' then
      return true
    elsif check_script == 'internal:make' then
      return check_internal_make(dir)
    else
      return check_external(check_script, dir)
    end
end

def check_internal_make(dir)
    return (system "make -C #{dir} clean") && (system "make -C #{dir}")
end

def check_external(check_script, dir)
    return (system "#{check_script} #{dir}")
end

def patch_and_check(patch, patchlevel, check_script)
  if not File.exist? patch then
    error "patch '#{patch}' does not exist"
  end

  puts
  puts
  puts "Patching #{patch}"
  patch_cmd = "patch -N -s -f -p#{patchlevel} -i #{patch}"
  puts patch_cmd.inspect
  if not system(patch_cmd)  then
    error "patching failed for '#{patch}'"
  end


  puts "Checking #{patch}"
  if not check(check_script) then
    error "check failed after applying patch '#{patch}'"
  end

  puts "Patch '#{patch}'' applied cleanly"


end


def main()
    check_script = 'internal:make'
    patchlevel = '0';
    pause = false


    optparse = OptionParser.new do | opts |
      opts.banner = "Usage: patch-and-check.rb [options] <patch1> [<patch2> [...]]"
        opts.on('-C', "--working-copy DIR", "Path to a working copy to which to apply patches. (default iscurrent working directory)") do | s |
            $DIR_WORK = s
        end
        opts.on('-c', "--check SCRIPT", "Path to script to check whether current working version is good or bad (default is to run make)") do | s |
            check_script = s
        end
        opts.on('-p', "--strip NUM", "Strip  the  smallest  prefix containing num leading slashes from each file name found in the patch file. This option is passed at it is to `patch`") do | s |
            patchlevel = s
        end
        opts.on(nil, '--pause', "Stop after each successfuly applied patch, waiting for user to confirm.") do
            pause = true
        end

        opts.on(nil, '--help', "Prints this message") do
            puts DOCUMENTATION
            puts optparse.help()
            exit 0
        end
    end

    optparse.parse!

    if not File.exist? $DIR_WORK then
      error("Working directory does not exist")
    end
    if not File.directory? $DIR_WORK then
      error("Working directory is not directory")
    end

    patches = ARGV
    patches.collect! do | each |
      File.expand_path each
    end

    if patches.size == 0 then
      error "No patches specified"
    end

    puts "Will apply following patches in order:"
    patches.each do | patch |
      puts patch
    end

    Dir.chdir($DIR_WORK) do
      patches.each do | patch |
        patch_and_check(patch,patchlevel, check_script)
        if pause then
          puts "Press enter key to continue (CTRL-C to abort)"
          ignored = STDIN.gets
        end
      end
    end
end

main()

