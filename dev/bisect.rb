#!/usr/bin/ruby
#
# A simple script to biset two directories. Prints the minimal set
# of files that differ and cause check to fail. 
#

require 'fileutils'
require 'tmpdir'
require 'optparse'

include FileUtils

def check(dir)
    #return (system "./check.sh #{dir}")
    return check_make(dir)
end

def check_make(dir)    
    return (system "make -C #{dir}")
end

def copy_files(files, src_dir, dst_dir)
    files.each do | f |
    	cp "#{src_dir}/#{f}", "#{dst_dir}/#{f}"
    end
end

def judge(suspects)
	puts
	puts 
	puts "JUDGING"
	suspects.each do | each |
            puts " - #{each}"
	end	
        copy_files(suspects, $DIR_BAD, $DIR_WORK)
        if ! check($DIR_WORK) then
            puts "GUILTY"
            suspects.each do | each |
            	puts " - #{each}"
            end
            Kernel.exit 1
        end
        copy_files(suspects, $DIR_GOOD, $DIR_WORK)
        if ! check($DIR_WORK) then
           puts "OOPS - working directory failed to check after reverting changes!" 
           Kernel.exit 11
        else 
	    puts "CONSIDERED INNOCENT"
	    suspects.each do | each |
                puts " - #{each}"
	    end

        end
        return false
end


def main()	
    excludes = []

    optparse = OptionParser.new do | opts |
    	opts.banner = "Usage: bisect-dir.rb [options] <good> <bad> <working>"        
    	opts.on('-X', '--exclude PATTERN', "Exclude files matching PATTERN from list of suspects") do | pattern |
            excludes << pattern
        end    		   
    end
    optparse.parse!
    

    $DIR_GOOD=ARGV[0]
    $DIR_BAD=ARGV[1]
    $DIR_WORK=ARGV[2]



    puts "Bisecting"
    puts " good : #{$DIR_GOOD}"
    puts " bad  : #{$DIR_BAD}"
    puts " work : #{$DIR_WORK}"

    puts "Diffing directories..."
    differences = `diff -x CVS -x .svn -x .hg -x \*.so -x \*.o -rqb #{$DIR_GOOD} #{$DIR_BAD} | grep differ`
    differences = differences.split("\n");
    differences = differences.map { |e| e.split()[1].slice($DIR_GOOD.size..-1) }
    excludes.each do | pattern |
    	re = Regexp.new(pattern)
    	differences = differences.reject { | f | f.match(re) }
    end
    
    
    puts "Files that differ: "
    differences.each do | each |
        puts " - #{each}"
    end

    puts "Preparing working directory..."
    `rsync --progress -r "#{$DIR_GOOD}/" "#{$DIR_WORK}/"`

    puts "Checking pristine working directory..."
    if ! check($DIR_WORK) then
    	puts "OOPS - pristing working directory failed to check!"
        Kernel.exit 10
    end

    for i in 1..differences.size
        differences.combination(i).each do | combination |    
            judge(combination)
        end         
    end    

    puts
    puts "OOPS - All prooven innocent. You've got wrong guys!"
end

main()
