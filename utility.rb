require 'rubygems'
require 'json'
require 'optparse'
require 'ostruct'
require 'logger'

class Optparse

  def self.parse(args)
    # The options specified on the command line will be collected in *options*.
    # We set default values here.
    options = OpenStruct.new
    options.folder_to_check = ""
    options.look_at_level = 1
    options.default_directory = 444
    options.default_file = 555
    options.change_permission = 0
    options.log_file = "/var/log/watch_permissions.log"

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: program [OPTIONS]"
      opts.separator  ""
      opts.separator  "Options"

      # Mandatory argument.
      opts.on("-w","--write [bool]","1 => change permissions, 0 => log") do |write|
        options.change_permission = write
      end      

      opts.on("-c","--folder_to_check [folder]","which folder to scan !!Full path without slash at the end!!") do |folder_to_check|
        options.folder_to_check = folder_to_check
      end

      opts.on("-p","--look_at_level [level]",
                  [:first, :second],
                  "how deep to look for permission.json (only first => ./permission.json./, second => ./*/permission.json)") do |look_at_level|
        options.look_at_level = look_at_level
      end

      opts.on("-l","--log_file [file]","specifi log file") do |log_file|
        options.log_file = log_file
      end

      opts.on("-d","--default_directory [HEX]","set default mask for folders") do |default_directory|
        options.default_directory = default_directory
      end

      opts.on("-f","--default_file [HEX]","set default mask for files") do |default_file|
        options.default_file = default_file
      end
      
      opts.separator ""
      opts.separator "Typical usage"
      opts.separator "\truby utility.rb -w true -c /var/www -p second -d 555 -f 444 -l /var/log/test.log"
      
      
      opts.separator ""
      opts.separator "other options:"

      # No argument, shows at tail.  This will print an options summary.
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      # Another typical switch to print the version.
      opts.on_tail("-v","--version", "Show version") do
        puts OptionParser::Version.join('.')
        exit
      end
    end

    opt_parser.parse!(args)
    options
  end  # parse()

end  # class Optparse

class Checker
  #určuje defaultní souborovou masku
  attr_accessor :DEFAULT_PERMISSION_FILE
  attr_accessor :DEFAULT_PERMISSION_FOLDER
  # true = bude přepisovat oprávnění
  attr_accessor :CHANGE_PERMISSION
  # procházená složka
  attr_accessor :DEFAULT_DIRECTORY
  # kde hledá permission.json
  attr_accessor :LEVEL
  # adresa logu
  attr_accessor :log_file
  
  
  # konstruktor
  def initialize(dpf, dpff, rewrite, dir, level,log)
    @DEFAULT_PERMISSION_FOLDER = dpf
    @DEFAULT_PERMISSION_FILE = dpff
    if rewrite
      @CHANGE_PERMISSION = true
    else
      @CHANGE_PERMISSION = false
    end
    @DEFAULT_DIRECTORY = dir
    @LEVEL = level
    @log_file = log
    begin
      $logger = Logger.new(@log_file, 'daily')
    rescue Exception=>e
      puts "[FATAL ERROR] #{e}"
      exit
    end
    $logger.info("***************")
    $logger.info("NEW PROGRAM RUN")
    $logger.info("***************")
    $logger.info("ARGS:")
    $logger.info("default permissions for files: #{@DEFAULT_PERMISSION_FILE}")
    $logger.info("default permissions for folders: #{@DEFAULT_PERMISSION_FOLDER}")
    $logger.info("change permission: #{@CHANGE_PERMISSION}")
    $logger.info("directory to check: #{@DEFAULT_DIRECTORY}")
    $logger.info("deep level check: #{@LEVEL}")
  end # method initialize

  def run
    #defaultní cesta (vstup)
    Dir.chdir(@DEFAULT_DIRECTORY)

    #první řád složek
    rootFolders = Dir.glob("*/") 

    runScan(rootFolders,@DEFAULT_DIRECTORY)
  end # method run

  #testování příznaku souborů určených v souboru permission.json
  def isPermisionOK(file,permission,dirPath)
    begin
        wr=`stat --format=%a #{dirPath}#{file}`.chomp
      rescue Exception=>e
        $logger.fatal("external program thrown error")
        $logger.fatal(e)
        exit
      else
        if wr==permission
          return true
        else
          $logger.warn("file #{dirPath}#{file} has #{wr} should be #{permission}")
          if @CHANGE_PERMISSION
            $logger.warn("Changing permission of file #{dirPath}#{file} from  #{wr} to #{permission}")
            begin
              `chmod #{permission} #{dirPath}#{file}`
            rescue Exception=>e
              $logger.fatal("external program thrown error")
              $logger.fatal(e)
              exit
            end
            return false
          end
        end
    end
  end # method isPermisionOK

  #testování příznaku souborů neurčených v souboru permission.json
  def isPermisionOKDefault(file,dirPath)
    begin
      wr=`stat --format=%a #{dirPath}#{file}`.chomp
      wd=`stat --format=%F #{dirPath}#{file}`.chomp
    rescue Exception=>e
        $logger.fatal("external program thrown error")
        $logger.fatal(e)
        exit
    else
      case wd
         when "directory" then default_permission = @DEFAULT_PERMISSION_FOLDER
         when "regular file" then default_permission = @DEFAULT_PERMISSION_FILE
         else $logger.fatal("Invalid file type #{wd} #{dirPath}#{file}")
      end
  
      if wr==default_permission
        return true
      else
        $logger.warn("file #{dirPath}#{file} has #{wr} should be #{default_permission}")
        if @CHANGE_PERMISSION
          $logger.warn("Changing permission of file #{dirPath}#{file} from  #{wr} to #{default_permission}")
            begin
              `chmod #{default_permission} #{dirPath}#{file}`
            rescue Exception=>e
              $logger.fatal("external program thrown error")
              $logger.fatal(e)
              exit
            end
          return false
        end
      end
    end
  end # method isPermisionOKDefault

  #Testování souborů určených v souboru permission.json
  def checkFoldersPermisionFile(dirPath, json, fileHash)
    $logger.info("Check of files in permission.json")
    json.each do |fileName, permission|
      begin
        wd=`stat --format=%F #{dirPath}#{fileName}`.chomp
       rescue Exception=>e
        $logger.fatal("external program thrown error")
        $logger.fatal(e)
        exit
      else
        if wd=="directory"
          Dir.chdir("#{dirPath}#{fileName}")
          ifIsPermisionOK("#{fileName}",permission,dirPath)
          fileHash["#{fileName}"]= true
          
          Dir.glob("**/*").each do |f|
            if !fileHash["#{fileName}/#{f}"]
              ifIsPermisionOK("#{fileName}/#{f}",permission,dirPath)
              fileHash["#{fileName}/#{f}"]= true
            end
          end
        else
          if !fileHash[fileName]
            ifIsPermisionOK(fileName,permission,dirPath)
            fileHash["#{fileName}"]= true
          end
        end
      end
    end
    return fileHash 
  end # method checkFoldersPermisionFile

  #opakující se dvojtá podmínka
  def ifIsPermisionOK(fileName,permission,dirPath)
    if !isPermisionOK(fileName,permission,dirPath)
      if !isPermisionOK(fileName,permission,dirPath)
        $logger.fatal("Can't chage permission of the file #{dirPath}#{fileName}")
      end
    end
  end # method ifIsPermisionOK

  #Testování souborů neuvedených v souboru permission.json
  def checkFoldersForDefaultPermision(dirPath, fileHash)
    $logger.info("Check of files outside permission.json")
    fileHash.each do |fileName, isChecked| 
      if !isChecked
        if !isPermisionOKDefault(fileName,dirPath)
          if !isPermisionOKDefault(fileName,dirPath)
            $logger.fatal("Can't chage permission of the file #{dirPath}#{fileName}")
          end
        end
      end
      fileHash["#{fileName}"]= true
    end

    return fileHash 
  end # method checkFoldersForDefaultPermision


  def runScan(rootFolders,folder)
    #cyklus procházení složek prvního řádu
    rootFolders.each do |rootFolder|
      dirPath = "#{folder}/#{rootFolder}"
      Dir.chdir(dirPath)

      #hash tabulka se všemi soubory v adresáři
      fileHashTmp = Dir.glob("**/*").collect { |f| [f, false] }
      fileHash = Hash[fileHashTmp]

      #testovaní existence permissions.json ve složce
      begin
        #otevreni souboru nastaveni
        file = File.open("#{dirPath}permissions.json", &:read)
      rescue Exception=>e
        $logger.fatal(e.message)
        $logger.warn("Skiping folder #{dirPath}")
      else
        json=JSON.parse(file)
        #rutina pro veškerou práci se souborem permissions.json
        checkFoldersPermisionFile(dirPath, json, fileHash)
        #rutina pro veškerou práci se soubory nedefinovanými v permission.json
        checkFoldersForDefaultPermision(dirPath,fileHash)
      end
    end
  end # method runScan
end # class Checker


options = Optparse.parse(ARGV)

checker = Checker.new(options.default_directory,options.default_file,options.change_permission,options.folder_to_check,options.look_at_level,options.log_file)
checker.run()