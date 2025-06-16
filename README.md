This repository contains a bunch of scripts that helps me with the development
and maintenance. May or may not be useful for other people :-)

Scripts
-------

* *[bisect.rb][1]*: a tool to find a minimal set of files causing a problem. Similar to `git bisect` or `hg bisect` but usable standalone and even for non-git, non-hg sources.

* *[patch-and-check.rb][2]*: a simple tool to apply a set of patches and verify patched sources. Handy when transplating changes from one branch to another and SCM is not of much help (such as cross-SCM)

* *[stx-pkg-rename.rb][3]*: renaming a Smalltalk/X package is sort of a pain. This script makes it a little bit easier.

* *[stx-cls-rename.rb][18]*: renaming a Smalltalk/X class on a file level requires changing build support files as well. This script automates this. However, it's always better to Smalltalk/X IDE to do so! Use only if you know what are you doing. 

* *[stx-normalize-trace-log.rb][10]* a script to normalize a trace output from Smalltalk/X VM so difference in two traces can be easily spotted using text diff tool. 

* *[hg-archive-revisions.rb][4]*: an `hg archive` wrapper which allows to export multiple revisions at once, in the same way `hg export` can. Handy for generating complete archives for those who don't like patches :-)

* *[hg-xplant.rb][5]*: a script to transplant changes from Mercurial repository to other, non-Mercurial working copy (such as CVS checkout).

* *[hg-xpull.rb][11]*: a script to incrementally pull changes from non-mercurial repository (using a convert extension). Handy when a forest of Mercurial repositories are forked off a non-Mercurial upstream (such as those of [Smalltalk/X jv-branch][12]).

* *[hg-automerge.rb][13]*: a script to automate branch merge. May be used in
conjunction with [hg-xpull.rb][11] to automatically merge changes in upstream.

* *[hgf.rb][14]*: a script to execute command on all repositories in a repository forest. 

* *[cvs-addremove.rb][6]* a script to examine  CVS working copy, `cvs add` allnew files and `cvs remove` all missing files.

* *[bitbucket-sync.rb][16]* a simple script for bi-directional synchronization of BitBucket-hosted repositories with local mirror

* *[smb-sync.rb][17]* a simple script to synchronize SMB/CIFS share to a local directory.

* *[stx-pkg-fork-cvs.rb][19]*: a script to make a (Mercurial) fork of Smalltalk/X package from CVS

* *[zcpy.sh][20]*: a simple script to (incrementally) copy ZFS datasets between pools WITHIN ONE SYSTEM.

* *[github-sync.py][21]*: a simple script for uni-directional synchronization of GitHub repositories.

* *[get-oauth2-token.py][22]*: script to get Outh2 access token (for example, to access mail through IMAPS on Office365).

* *[github-activity.py][23]*: script to print activity summary of GitHub repositories over a period of time.


You can find more details about inside these scripts, or run script with `--help`.
More scripts will come as I polish them :-)

Installation
------------

Just clone the repository to some location and add it to the `PATH`. 

However, you may need to install Ruby to run Ruby scripts (those with `.rb` suffix)

[1]: https://github.com/janvrany/scripts/blob/master/bisect.rb
[2]: https://github.com/janvrany/scripts/blob/master/patch-and-check.rb
[3]: https://github.com/janvrany/scripts/blob/master/stx-pkg-rename.rb
[4]: https://github.com/janvrany/scripts/blob/master/hg-archive-revisions.rb
[5]: https://github.com/janvrany/scripts/blob/master/hg-xplant.rb
[6]: https://github.com/janvrany/scripts/blob/master/cvs-addremove.rb
[10]: https://github.com/janvrany/scripts/blob/master/stx-normalize-trace-log.rb
[11]: https://github.com/janvrany/scripts/blob/master/hg-xpull.rb
[12]: https://swing.fit.cvut.cz/projects/stx-jv
[13]: https://github.com/janvrany/scripts/blob/master/hg-automerge.rb
[14]: https://github.com/janvrany/scripts/blob/master/hgf.rb
[16]: https://github.com/janvrany/scripts/blob/master/bitbucket-sync.rb
[17]: https://github.com/janvrany/scripts/blob/master/smb-sync.rb
[18]: https://github.com/janvrany/scripts/blob/master/stx-cls-rename.rb
[19]: https://github.com/janvrany/scripts/blob/master/stx-pkg-fork-cvs.rb
[20]: https://github.com/janvrany/scripts/blob/master/zcpy.sh
[21]: https://github.com/janvrany/scripts/blob/master/github-sync.py
[22]: https://github.com/janvrany/scripts/blob/master/get-oauth2-token.py
[23]: https://github.com/janvrany/scripts/blob/master/github-activity.py