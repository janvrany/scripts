This repository contains a bunch of scripts that helps me with the development
and maintenance. May or may not be useful for other people :-)

Scripts
-------

* *[bisect.rb][1]*: a tool to find a minimal set of files causing a problem. Similar to `git bisect` or `hg bisect` but usable standalone and even for non-git, non-hg sources.

* *[patch-and-check.rb][2]*: a simple tool to apply a set of patches and verify patched sources. Handy when transplating changes from one branch to another and SCM is not of much help (such as cross-SCM)

* *[stx-pkg-rename.rb][3]*: renaming a Smalltalk/X package is sort of a pain. This script makes it a little bit easier.

* *[stx-normalize-trace-log.rb][10]* a script to normalize a trace output from Smalltalk/X VM so difference in two traces can be easily spotted using text diff tool. 

* *[hg-archive-revisions.rb][4]*: an `hg archive` wrapper which allows to export multiple revisions at once, in the same way `hg export` can. Handy for generating complete archives for those who don't like patches :-)

* *[hg-xplant.rb][5]*: a script to transplant changes from Mercurial repository to other, non-Mercurial working copy (such as CVS checkout).

* *[hg-xpull.rb][11]*: a script to incrementally pull changes from non-mercurial repository (using a convert extension). Handy when a forest of Mercurial repositories are forked off a non-Mercurial upstream (such as those of [Smalltalk/X jv-branch][12]).


* *[cvs-addremove.rb][6]* a script to examine  CVS working copy, `cvs add` allnew files and `cvs remove` all missing files.

* *[bee-pkg-set.rb][7]* simple script to set package name in Bee Smalltalk changeset file (.ch)

* *[bee.rb][8]* script to run Bee Smalltalk under WINE. 

* *[bee-config.rb][9]* convenience script to open an editor on Bee Smalltalk config file (used by `bee.rb`).


You can find more details about inside these scripts, or run script with `--help`.
More scripts will come as I polish them :-)

Installation
------------

Just clone the repository to some location and add it to the `PATH`. 

However, you may need to install Ruby to run Ruby scripts (those with `.rb` suffix)

[1]: https://bitbucket.org/janvrany/jv-scripts/src/tip/bisect.rb
[2]: https://bitbucket.org/janvrany/jv-scripts/src/tip/patch-and-check.rb
[3]: https://bitbucket.org/janvrany/jv-scripts/src/tip/stx-pkg-rename.rb
[4]: https://bitbucket.org/janvrany/jv-scripts/src/tip/hg-archive-revisions.rb
[5]: https://bitbucket.org/janvrany/jv-scripts/src/tip/hg-xplant.rb
[6]: https://bitbucket.org/janvrany/jv-scripts/src/tip/cvs-addremove.rb
[7]: https://bitbucket.org/janvrany/jv-scripts/src/tip/bee-pkg-set.rb
[8]: https://bitbucket.org/janvrany/jv-scripts/src/tip/bee.rb
[9]: https://bitbucket.org/janvrany/jv-scripts/src/tip/bee-config.rb
[10]: https://bitbucket.org/janvrany/jv-scripts/src/tip/stx-normalize-trace-log.rb
[11]: https://bitbucket.org/janvrany/jv-scripts/src/tip/hg-xpull.rb
[12]: https://swing.fit.cvut.cz/projects/stx-jv