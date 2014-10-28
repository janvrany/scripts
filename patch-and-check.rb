#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
A simple script to apply a sequence of .patch files and after each
check if it applied cleanly.

Useful when you have two possibly diverging lines of development in two
different SCMs and want to transpant fixes done in one line on top of a
head in the other (such as transplating changes from HG to on top of CVS HEAD)

The check script (if provided) is passed a path to working directory and must
return exit status 0 if working copy is good of nonzero if its bad.

There are two "built-in" check scripts:

  * "internal:make" (the default, if no check script is used) which just runs
     a make. A patch is consireded good if make proceeds without errors.
  * "internal:none" a patch is slways consireded good (as long as patching
     proceeds fine)

Optionally an archive is saved after each patch is applied and validated,
in which case the name of the file is given using a format string. The
formatting rules are as follows:

    "%%"          literal "%" character
    "%1"          zero-padded number `1`
    "%n"          zero-padded sequence number, starting at 1
    "%N"          number of patches being applied
    "%P"          basename of patch file without last suffix.

Examples:


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
    retval = (system "make -C #{dir} clean") && (system "make -C #{dir}")
    system "make -C #{dir} clean"
    return retval
end

def check_external(check_script, dir)
    return (system "#{check_script} #{dir}")
end

def patch_and_check(patch, patchlevel, check_script)
  if not File.exist? patch then
    error "Patch '#{patch}' does not exist"
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

def archive(patch, patch_no, patches_total, fmt)
  _fmt = fmt
  _fmt = _fmt.gsub(/\%/, '%%')
  _fmt = _fmt.gsub(/\%\%n/, '%{n}')
  _fmt = _fmt.gsub(/\%\%N/, '%{N}')
  _fmt = _fmt.gsub(/\%\%P/, '%{P}')


  if patches_total < 10 then
    _fmt = _fmt.gsub(/\%\%1/, '1')
    fmt_n = "%01d"
  elsif patches_total < 100 then
    _fmt = _fmt.gsub(/\%\%1/, '01')
    fmt_n = "%02d"
  elsif patches_total < 1000 then
    _fmt = _fmt.gsub(/\%\%1/, '001')
    fmt_n = "%03d"
  elsif patches_total < 10000 then
    _fmt = _fmt.gsub(/\%\%1/, '0001')
    fmt_n = "%04d"
  else
    _fmt = _fmt.gsub(/\%\%1/, '00001')
    fmt_n = "%05d"
  end

  archive_file = _fmt % { :n => (fmt_n % patch_no),
                          :N => (fmt_n % patches_total),
                          :P => patch.sub(/\.[^\.]+$/,'').sub(/^.*\//,'') }
  archive_dir = archive_file.sub(/\.zip$/,'').sub(/^.*\//,'')
  puts "Archiving #{patch} to #{archive_file}"
  Dir.mktmpdir do | tmpdir |
    ln_s($DIR_WORK, File.join(tmpdir, archive_dir))
    Dir.chdir tmpdir do
      system 'ls'
      zip_cmd = "zip -r #{archive_file} #{archive_dir} -x \"*.o\" -x \"*.obj\" -x \".orig\" -x \".rej\" -x \".#*\""
      puts zip_cmd
      if not system(zip_cmd) then
        error("Cannot create archive '#{archive_file}'")
      end
    end
  end
end

def main()
    check_script = 'internal:make'
    patchlevel = '1';
    interactive = false
    archive = false;
    archive_fmt = nil


    optparse = OptionParser.new do | opts |
      opts.banner = "Usage: patch-and-check.rb [options] <patch1> [<patch2> [...]]"
        opts.on('-C', "--working-copy DIR", "Path to a working copy to which to apply patches. (default iscurrent working directory)") do | s |
            $DIR_WORK = s
        end
        opts.on('-c', "--check SCRIPT", "Path to script to check whether current working version is good or bad (default is to run make)") do | s |
            check_script = s
        end
        opts.on('-p', "--strip NUM", "Strip  the  smallest  prefix containing num leading slashes from each file name found in the patch file. This option is passed at it is to `patch`. Default is '1'.") do | s |
            patchlevel = s
        end
        opts.on('-i', '--interactive', "Stop after each successfuly applied patch, waiting for user to confirm.") do
            interactive = true
        end
        opts.on('-a', '--archive FORMAT', "Export .zip archive of code after applying each patch.") do | s |
            archive = true
            archive_fmt = File.expand_path s
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
    elsif  not File.directory? $DIR_WORK then
      error("Working directory is not directory")
    else
      $DIR_WORK =  File.expand_path $DIR_WORK
    end

    patches = ARGV
    patches.collect! do | each |
      File.expand_path each
    end

    if patches.size == 0 then
      error "No patches specified"
    end

    if interactive then
      puts "Will apply following patches in order:"
      for i in 0..patches.size - 1
        patch = patches[i]
        puts "#{i+1} #{patch.sub(/\.[^\.]+$/,'').sub(/^.*\//,'')}"
      end
    end

    Dir.chdir($DIR_WORK) do
      for i in 0..patches.size - 1 do
        patch = patches[i]

        patch_and_check(patch, patchlevel, check_script)
        if archive then
          archive(patch, i + 1, patches.size, archive_fmt)
        end

        if interactive then
          if (i < (patches.size - 1)) then
            puts "Next patch is #{patches[i+1]}"
          end
          puts "Press enter key to continue (CTRL-C to abort)"
          ignored = STDIN.gets
        end
      end
    end
end

main()

