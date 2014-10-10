This repository contains a bunch of scripts that helps me with the development
and maintenance. May or may not be useful for other people :-)

Scripts
-------

* *bisect.rb*: a tool to find a minimal set of files causing a problem. Similar to `git bisect` or `hg bisect` but usable standalone and even for non-git, non-hg sources.

* *stx-pkg-rename.rb*: renaming a Smalltalk/X package is sort of a pain. This script makes it a little bit easier.

* *hg-archive-revisions.rb*: an `hg archive` wrapper which allows to export multiple revisions at once, in the same way `hg export` can. Handy for generating complete archives for those who don't like patches :-)

You can find more details about inside these scripts, or run script with `--help`.
More scripts will come as I polish them.

Installation
------------

Each script is standalone, so just copy it wherever convenient for you and run it.
However, you may need to install Ruby to run Ruby scripts (those with `.rb` suffix)