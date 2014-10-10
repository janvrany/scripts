#!/usr/bin/ruby
DOCUMENTATION = <<DOCEND
hg-archive-revisions.rb [OPTION] [-o OUTFILESPEC] [-r] [REV]

export a complete archive for one or more changeses.

    Pretty much like `hg export` but exports contents, not
    patches.

    Output may be to a file, in which case the name of the file is given using
    a format string. The formatting rules are as follows:

    "%%"          literal "%" character
    "%H"          changeset hash (40 hexadecimal digits)
    "%1"          zero-padded number `1`
    "%N"          number of archives being generated
    "%R"          changeset revision number
    "%b"          basename of the exporting repository
    "%h"          short-form changeset hash (12 hexadecimal digits)
    "%m"          first line of the commit message (only alphanumeric
                  characters)
    "%n"          zero-padded sequence number, starting at 1
    "%r"          zero-padded changeset revision number

DOCEND

require 'fileutils'
require 'tmpdir'
require 'optparse'

def error(message, code=1)
  puts "error: #{message}"
  exit code
end

def fixformat(fmt, numrevs)
  fmt.gsub!(/\%/, '%%')
  fmt.gsub!(/\%\%n/, '%{n}')
  fmt.gsub!(/\%\%N/, '%{N}')

  if numrevs < 10 then
    fmt.gsub!(/\%\%1/, '1')
    fmt_n = "%01d"
  elsif numrevs < 100 then
    fmt.gsub!(/\%\%1/, '01')
    fmt_n = "%02d"
  elsif numrevs < 1000 then
    fmt.gsub!(/\%\%1/, '001')
    fmt_n = "%03d"
  elsif numrevs < 10000 then
    fmt.gsub!(/\%\%1/, '0001')
    fmt_n = "%04d"
  else
    fmt.gsub!(/\%\%1/, '00001')
    fmt_n = "%05d"
  end
end

def main()
  ffmt = "%h.zip"
  pfmt = ''
  revset = 'p1()'
  type = 'files'

  optparse = OptionParser.new do | opts |
    opts.banner = "options:\n"
    opts.on('-r', "revisions to export") do
    end

    opts.on('-o', '--output [FORMAT]', "save archive to file with formatted name") do | value |
      ffmt = value
    end
    opts.on('-t', '--type [TYPE]', "type of distribution to create (see hg archive for details") do | value |
      type = value
    end
    opts.on('-p', '--prefix [PREFIX]', "directory prefix for files in archive (see hg archive for details") do | value |
      pfmt = value
    end
    opts.on(nil, '--help', "prints this message") do
      puts DOCUMENTATION
      puts optparse.help()
      exit 0
    end

  end

  optparse.parse!

  revset = ARGV[0]
  cmd = "hg log -r \"sort(#{revset}, 'date')\" --template \"{node}\\n\""
  revs = `#{cmd}`.split(/\n/)

  if (revs.size == 0)
    error("No changesets selected")
  end

  fixformat(ffmt, revs.size)
  fixformat(pfmt, revs.size)
  if revs.size < 10 then
    fmt_n = "%01d"
  elsif revs.size < 100 then
    fmt_n = "%02d"
  elsif revs.size < 1000 then
    fmt_n = "%03d"
  elsif revs.size < 10000 then
    fmt_n = "%04d"
  else
    fmt_n = "%05d"
  end

  for n in 0..(revs.size - 1) do
    rev = revs[n]
    fname = ffmt % {:n => (fmt_n % (n + 1)), :N => revs.size }
    prefix = pfmt % {:n => (fmt_n % (n + 1)), :N => revs.size }

    if (prefix.size > 0) then
      puts "Archiving #{rev} to #{fname} (prefix #{prefix})"
      prefix_arg = "--prefix \"#{prefix}\""
    else
      puts "Archiving #{rev} to #{fname}"
    end
    hgcmd = "hg archive #{prefix_arg} -t #{type} -r #{rev} #{fname}"
    if not system(hgcmd) then
      error("hg failed: #{hgcmd}");
    end
  end

end

main()
