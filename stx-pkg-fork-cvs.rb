#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
Fork Smalltalk/X package

This script automates forking of Smalltalk/X packages in CVS into Mercurial
repository. Namely:

 * creates a Mercurial repository,
 * sets it up to (incrementally) pull changes from CVS into 'default' branch
   (thanks to hg-xpull.hg script) and
 * creates a branch for further development of the fork

DOCEND

require 'fileutils'
require 'tmpdir'
require 'optparse'

def error(message, code=1)
  $LOGGER.error(message)
  puts "error: #{message}"
  exit code
end

$:.push(File.dirname($0))
require 'hglib'


HGRC = <<DEFEND

[web]
description = Fork of %s from %s
contact = %s

[xpull]
# Configuration for hg-xpull, see
#
#     https://bitbucket.org/janvrany/jv-scripts/src/tip/hg-xpull.rb
#
# Repository from which to pull and convert changes. For now,
# only CVS repositories are supported. Mandatory.
#
# repository = :pserver:cvs@cvs.smalltalk-x.de:/cvs/stx
repository = %s

# For CVS repositories, a subdirectory within that CVS repo. Mandatory for CVS
# repositories. Ignored for all others.
#
# repository-subdir = stx/projects/tinytalk
repository-subdir = %s

[xpull-authormap]
# This section defines an authormap used when converting commits. Optional.
# For more details see:
#
#    https://www.mercurial-scm.org/wiki/ConvertExtension#A--authors_.2F_--authormap
#
# Format is <upstream name> = <converted name>, for example:
#
# jdoe = John Doe <john@doe.org>
# ivan = Ivan Ivanovic <ivan@ivanovic.home>

[xpull-branchmap]
# This section defines a banchmap used when converting commits. Optional.
# For more details see:
#
#    https://www.mercurial-scm.org/wiki/ConvertExtension#A--branchmap
#
# Format is <upstream branch> = <converted branch>. For CVS repositorues,
# the "main" branch is named MAIN. To pull commits from CVS upstream (no-branch)
# into mercurial branch say 'cvs_MAIN', use
#
# MAIN = cvs_MAIN

[automerge]
# Automatically merge pulled changes from specified mercurial branch (if exists)
# to specified mercurial branch (if exists). The syntax is
#
# automerge = <from-branch>:<to branch>.
#
# The example below will merge changed from branch `default` to branch `jv`.
# If merge fails, issue a warning but proceed. Optional.
#
# automerge = default:jv
# automerge = default:jv

DEFEND

def fork(cvsroot, cvsdir, hgrepopath, hgbranchname)
  # Create mercurial repository:
  if (HG::repository? hgrepopath) then
    error("Mercurial repository already exists: #{hgrepopath}")
  end
  hgrepo = HG::Repository::init(hgrepopath)

  # Configure repository - most importantly, configure hg-xpull.
  File.open(hgrepo.hgrc, "w") do | file |
    file.write(HGRC % [ cvsdir, cvsroot, hgrepo.config['ui']['username'], cvsroot, cvsdir])
  end

  # Run hg-xpull.rb to populate the repository
  system "#{File.dirname($0)}/hg-xpull.rb --cwd #{hgrepopath}"

  # Make branch
  tmprepopath = Dir.mktmpdir()
  tmprepo = HG::Repository::clone(hgrepopath, tmprepopath)
  tmprepo.update('tip')
  tmprepo.hg('branch', hgbranchname)
  tmprepo.commit("Creating branch #{hgbranchname}")
  tmprepo.hg('push', '--new-branch')
end


def main()
  cvsroot = ENV['CVSROOT'] || ':pserver:cvs@cvs.smalltalk-x.de:/cvs/stx'
  cvsdir = nil
  hgpath = nil
  hgbranch = 'jv'

  optparse = OptionParser.new do | opts |
    opts.banner = "Usage: stx-pkg-fork.rb --cvs CVSROOT -d|--directory DIRECTORY -o|--hg REPOSITORY\n\n"
    opts.on('--cvs', '--old CVSROOT') do | value |
      cvsroot = value
    end

    opts.on('-d', '--directory DIRECTORY', "Path within CVSROOT where the package is located") do | value |
      cvsdir = value
    end

    opts.on('-o', '--hg REPOSITORY', "Path to Mercurial repository to be created. Must not exist") do | value |
      hgpath = value
    end

    opts.on('-b', '--branch BRANCHNAME', "Create a branch for fork (defaults to 'jv')") do | value |
      hgbranch = value
    end

    opts.on(nil, '--help', "Prints this message") do
      puts DOCUMENTATION
      puts optparse.help()
      exit 0
    end
  end

  optparse.parse!

  if cvsdir == nil then
    puts "error: no CVS directory specified - use -d|--directory option"
    puts optparse.help()
    exit 0
  end

  if hgpath == nil then
    puts "error: no Mercurial repository specified - use --hg option"
    puts optparse.help()
    exit 0
  end

  fork(cvsroot, cvsdir, hgpath, hgbranch)
end

main()
