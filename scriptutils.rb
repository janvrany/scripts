# This file is not a standalone script. It contains a module
# with some commonly used utilities

require 'fileutils'

if not $LOGGER then
  if STDOUT.tty? then
    require 'logger'
    $LOGGER = Logger.new(STDOUT)
    $LOGGER.level = Logger::INFO  
  else 
    require 'syslog/logger'
    $LOGGER = Syslog::Logger.new($0)    
  end
end

module ScriptUtils
  include FileUtils

  @@DRYRUN = false

  module_function
  def dryrun() 
    return @@DRYRUN
  end

  module_function
  def dryrun=(b)
    @@DRYRUN = b
  end

  # Given `dir`ectory and a `command`, run the script and return true if it 
  # succeeded (exit code 0), false otherwise. 
  #
  # The command is interpreted by system shell (by means of ruby's system() 
  # method). Command can be arbitrary string. The directory to check can be 
  # passed to script as a parameter - #{dir} will be expanded to an actual 
  # directory path. 
  #
  # For convenience, several builtin command are recognized. The builtin 
  # commands are: 
  #
  #     * 'internal:make' - run make in the given directory.
  #
  module_function
  def check(dir, command)    
    if command == 'internal:make'    
      return sh "make -C #{dir}"
    else      
      return sh String.interpolate { command }
    end
  end

  # Evaluates given command using a shell. Return true if command
  # returns zero exit status, false otherwise.   
  # 
  # If ScriptUtils::dryrun is true, no command is acrually executed
  # and true is returned. 
  module_function
  def sh(*cmd) 
    $LOGGER.debug("shell: #{cmd.join(' ')}")
    if @@DRYRUN then
      return true
    else
      return system(*cmd)
    end
  end
end

