This repository contains a bunch of scripts that helps me with the development
and maintenance. May or may not be useful for other people :-)

Scripts
-------

* *[bisect.rb][1]*: a tool to find a minimal set of files causing a problem. Similar to `git bisect` or `hg bisect` but usable standalone and even for non-git, non-hg sources.

* *[patch-and-check.rb][2]*: a simple tool to apply a set of patches and verify patched sources. Handy when transplating changes from one branch to another and SCM is not of much help (such as cross-SCM)

* *[stx-pkg-rename.rb][3]*: renaming a Smalltalk/X package is sort of a pain. This script makes it a little bit easier.

* *[hg-archive-revisions.rb][4]*: an `hg archive` wrapper which allows to export multiple revisions at once, in the same way `hg export` can. Handy for generating complete archives for those who don't like patches :-)

* *[hg-xplant.rb][5]*: a script to transplant changes from Mercurial repository
to other, non-Mercurial working copy (such as CVS checkout).


You can find more details about inside these scripts, or run script with `--help`.
More scripts will come as I polish them :-)

Installation
------------

Each script is standalone, so just copy it wherever convenient for you and run it.
However, you may need to install Ruby to run Ruby scripts (those with `.rb` suffix)

[1]: https://bitbucket.org/janvrany/jv-scripts/src/tip/bisect.rb
[2]: https://bitbucket.org/janvrany/jv-scripts/src/tip/patch-and-check.rb
[3]: https://bitbucket.org/janvrany/jv-scripts/src/tip/stx-pkg-rename.rb
[4]: https://bitbucket.org/janvrany/jv-scripts/src/tip/hg-archive-revisions.rb
[5]: https://bitbucket.org/janvrany/jv-scripts/src/tip/hg-xplant.rb