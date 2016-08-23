# This file is not a standalone script. It contains a module
# with some commonly used utilities

require 'fileutils'

module ScriptUtils
  include FileUtils

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
      return system "make -C #{dir}"
    else      
      return system String.interpolate { command }
    end
  end  
end

