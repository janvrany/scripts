#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
hg-xplant.rb - a script to transplant changes from Mercurial repository to
other, non-Mercurial working copy (such as CVS checkout). It expects changes
in non-Mercurial repository to be converted to the source Mercurial repository
(by means of hg convert extension, for example).

The transplantation is done as following:
For given source repository (Mercurial) and destination working copy
(non-Mercurial) and for given goal revision and destination revision,

  1. Generate a diff between destination revision and goal revision.
  2. Apply the diff to destination, check if it applies cleanly.
     If not, indicate an error and terminate.
  3. Check the patched working copy using provided check script.
     If check script fails, indicate an error and terminate.
  4. Fabricate a (default) commit message to file ~message-log~
     and update destinations .hgxplantlog to conrain goal_rev
     as last revision

If script succeeds, you should carefully validate results. If everything
is ok, you may want to commit to non-Mercurial repository.

NOTES:

'destination revision' (--dest-rev) defaults to last revision recorded in
source's `.hg/shamap`

'base revision' (--base-rev) is not used to generate a diff, but it is used
to generate a log message. All commits between base rev and goal rev are
considered as transplanted. Base revision defaults latest recorded revision
in .hgxplantlog or, if that does not exist, to greates common ancestor
of destination revision and goal revision.

The check script (if provided) is passed a path to working directory and must
return exit status 0 if working copy is good of nonzero if its bad.

There are two "built-in" check scripts:

  * "internal:make" (the default, if no check script is used) which just runs
     a make. A patch is consireded good if make proceeds without errors.
  * "internal:none" a patch is slways consireded good (as long as patching
     proceeds fine)

DOCEND

require 'fileutils'
require 'tmpdir'
require 'optparse'
require 'tempfile'

include FileUtils
$DIR_WORK = '.'

def error(message, code=1)
  puts "error: #{message}"
  exit code
end

def pause(msg = "Press enter key to continue (CTRL-C to abort)")
  puts msg
  ignored = STDIN.gets
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

def patch_and_check(dst, patch, patchlevel, check_script)
  if not File.exist? patch then
    error "Patch '#{patch}' does not exist"
  end
  Dir.chdir dst do
    patch_cmd = "patch -N -s -f -p#{patchlevel} -i #{patch}"
    puts "Patching..."
    if not system(patch_cmd)  then
      if File.exist?(File.join(dst, 'CVS')) then
        puts "Patchig failed. You may revert CVS working copy by:"
        puts ""
        puts "    (cd #{dst} && cvs upd -C)"
        puts ""
      end
      error "patching failed for '#{patch}'"
    end
    puts "Checking..."
    if not check(check_script) then
      error "check failed after applying patch '#{patch}'"
    end
  end
end

def hg_log_validate_rev(repo, rev)
  cmd = "hg --cwd #{repo} log --rev \"#{rev}\" --template ''"
  out = `#{cmd}`
  return $?.success?
end

def hg_log(repo, revset, template = "{node|short}\n")
  cmd = "hg --cwd #{repo} log --rev \"#{revset}\" --template \"#{template}\""
  out = `#{cmd}`
  if not $?.success?
    puts "error: "
    puts out
    puts "^ command output ^"
    error("failed to execute: '#{cmd}' status: #{$?.exitstatus}")
  end
  return out.split("\n")
end

def hg_symbolic_rev_2_shortrev(repo, rev)
  return hg_log(repo, rev)[0].chop
end

def hg_wc_revision(repo)
  return hg_log(repo, '.')[0].chop
end


def hg_diff(repo, rev1, rev2)
  patch = Tempfile.new(["#{rev1}-#{rev2}-", '.patch'])
  patch = patch.path
  puts "Diffing to #{patch}"
  cmd = "hg --cwd #{repo} diff -r #{rev1} -r #{rev2} > #{patch}"
  system cmd
  if not $?.success? then
    error("Failed to generate diff")
  end
  return patch
end

def hg_xplant(src, dst, rev_goal, rev_dest, rev_base, revmap, check_script, dry_run = false)
  puts "Transplanting..."
  puts "  goal rev: #{rev_goal}"
  puts "  dest rev: #{rev_dest}"
  puts "  base rev: #{rev_base}"
  commits = hg_log(src, "#{rev_base}::#{rev_goal} - #{rev_base}::#{rev_dest}", "  - {node|short}: {author|person}, {date|isodate}: {firstline(desc)}\\n")
  puts "   commits: #{commits.size}"

  patch = hg_diff(src, rev_dest, rev_goal)
  if not dry_run then
    patch_and_check(dst, patch, 1, check_script)
  end
  if commits.size == 1 then
    commits = hg_log(src, "#{rev_base}::#{rev_goal} - #{rev_base}::#{rev_dest}", "{node|short}: {author|person}, {date|isodate}\n\n{desc}\\n")
  end

  # Generate default commit message
  log_message_file = File.join(dst, "~log-message~")
  File.open(log_message_file, "w") do | log_message |
    log_message.write("Merged with mercurial revision #{rev_goal}")
    if commits != nil and commits.size != 1 then
       log_message.write(" (#{commits.size} changesets total)\n\n")
       log_message.write("Merged changesets:\n")
    else
       log_message.write("\n\n")
    end
    commits.each do | commit |
      log_message.write(commit)
      log_message.write("\n")
    end
  end

  # Generate splicemap entry
  splicemap_entry = nil
  if (revmap.size > 0) then
    rev_base_full = (hg_log(src, rev_base, "{node}\n"))[0]
    splicemap_entry = "#{revmap.last[0].to_i + 1} #{revmap.last[0].to_i},#{rev_base_full}"
  end

  # Write .hgxplantlog
  if not dry_run then
    hgxplantlog_file = File.join(dst, ".hgxplantlog")
    File.open(hgxplantlog_file, "a") do | hgxplantlog |
      hgxplantlog.write("#{rev_goal}\n")
    end
  end



  puts "Transplanted."
  puts ""
  puts " * Generated commit message has been written to #{log_message_file} ."
  puts ""
  if splicemap_entry != nil then
  puts " * You may want to add following line to splicemap to record the mege:"
  puts ""
  puts "       #{splicemap_entry}"
  puts ""
  end
  if File.exist?(File.join(dst, 'CVS', 'Entries')) then
    puts " * Call cvs-addremove.rb to add/remove file in CVS:"
    puts ""
    puts "       cvs-addremove -C #{dst}"
    puts ""
    puts " * Commit to CVS:"
    puts ""
    puts "       (cd #{dst} && cvs commit -F ~log-message~)"
    puts ""
  end
end


def main()
    source = File.expand_path(".")
    destination = nil
    dry_run = false

    rev_goal = nil
    rev_dest = nil
    rev_base = nil

    check_script = 'internal:make'

    optparse = OptionParser.new do | opts |
      opts.banner = "Usage: hg-xplant.rb [options] [-r REV1] -d DESTINATION"
        opts.on("--dest DIRECTORY", "Directory to which transplant") do | s |
            destination = s
        end
        opts.on("--source DIRECTORY", "Working copy from which to transplant") do | s |
            source = s
        end

        opts.on("--goal-rev REV", "Transplant revision REV (default is source working copy revision)") do | s |
            rev_goal = s
        end
        opts.on("--dest-rev REV", "Mercurial revision of code in destination") do | s |
            rev_dest = s
        end
        opts.on('--base-rev REV", "Base revision of --goal-rev and --dest-rev. Used to generate log message. Defaults to latest recorded revision destination .hgxplantmap or greatest common ancestor or --goal-rev and --dest-dev.') do | s |
            rev_base = s
        end

        opts.on('-c', "--check SCRIPT", "Path to script to check whether patched destination is good or bad (default is to run make)") do | s |
            check_script = s
        end

        opts.on("--dry-run", "Do not update any files nor patch desctination. Use for testing.") do | s |
            dry_run = true
        end

        opts.on(nil, '--help', "Prints this message") do
            puts DOCUMENTATION
            puts optparse.help()
            exit 0
        end
    end
    optparse.parse!

    if not File.exist? source then
      error("source directory does not exist")
    elsif not File.directory? source then
      error("source directory is not directory")
    elsif not File.directory?(File.join(source, '.hg')) then
      error("source directory is not a Mercurial repository")
    end

    if destination == nil then
      error("destination not specified, Use --dest to specify destination.")
    elsif not File.exist? destination then
      error("destination directory does not exist")
    elsif not File.directory? destination then
      error("destination directory is not directory")
    end

    if rev_goal == nil then
      rev_goal = hg_wc_revision(source)
    elsif not hg_log_validate_rev(source, rev_goal) then
      error("goal revision #{rev_goal} does not exist")
    else
      rev_goal = hg_symbolic_rev_2_shortrev(source, rev_goal)
    end

    revmap_file = File.join(source, '.hg', 'shamap')
    revmap = []
    if File.exist?(revmap_file) then
      File.open(revmap_file, "r") do | file |
        file.each do | pair |
          revmap << pair.split(" ")
        end
      end
    end

    if rev_dest == nil then
      if File.exist?(revmap_file) then
        if revmap.size > 0 then
          rev_dest = revmap.last[1]
        else
          error("dest revision not specified and source's revmap (.hg/shamap) is empty")
        end
      else
        error("dest revision not specified and source's revmap (.hg/shamap) does not exist")
      end
    end
    if not hg_log_validate_rev(source, rev_dest) then
      error("dest revision #{rev_dest} does not exist")
    else
      rev_dest = hg_symbolic_rev_2_shortrev(source, rev_dest)
    end

    if rev_base == nil then
      hgxplantlog_file = File.join(destination, '.hgxplantlog')
      if File.exist?(hgxplantlog_file) then
        File.open(hgxplantlog_file, "r") do | file |
          file.each do | rev |
            rev_base = rev
          end
        end
      end
      if rev_base == nil then
        rev_base = hg_log(source, "ancestor(p1(#{rev_goal}), #{rev_dest})")
        if rev_base.size == 0 then
          error("Cannot find base revision as 'ancestor(p1(#{rev_goal}), #{rev_dest})'. Use --rev-base.")
        else
          rev_base = rev_base[0]
        end
      end
    end
    if not hg_log_validate_rev(source, rev_base) then
      error("base revision #{rev_base} does not exist")
    else
      rev_base = hg_symbolic_rev_2_shortrev(source, rev_base)
    end

    if rev_goal == rev_dest then
      error("goal revision equal to destination revision")
    end
    if rev_goal == rev_base then
      error("goal revision equal to base revision - commits may be already transplanted")
    end

    hg_xplant(source, destination, rev_goal, rev_dest, rev_base, revmap, check_script, dry_run)
end


main()

