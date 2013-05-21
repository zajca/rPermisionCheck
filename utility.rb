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
    options.change_permision = 0
    options.log_file = "/var/log/watch_permisions.log"

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: program [OPTIONS]"
      opts.separator  ""
      opts.separator  "Options"

      # Mandatory argument.
      opts.on("-w","--write [bool]","1 => change permisions, 0 => log") do |write|
        options.change_permision = write
      end      

      opts.on("-c","--folder_to_check [folder]","which folder to scan !!Full path without slash at the end!!") do |folder_to_check|
        options.folder_to_check = folder_to_check
      end

      opts.on("-p","--look_at_level [level]",
                  [:first, :second],
                  "how deep to look for permision.json (only first => ./permision.json./, second => ./*/permision.json)") do |look_at_level|
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
  attr_accessor :DEFAULT_PERMISION_FILE
  attr_accessor :DEFAULT_PERMISION_FOLDER
  # true = bude přepisovat oprávnění
  attr_accessor :CHANGE_PERMISION
  # procházená složka
  attr_accessor :DEFAULT_DIRECTORY
  # kde hledá permision.json
  attr_accessor :LEVEL
  # adresa logu
  attr_accessor :log_file
  
  
  # konstruktor
  def initialize(dpf, dpff, rewrite, dir, level,log)
    @DEFAULT_PERMISION_FOLDER = dpf
    @DEFAULT_PERMISION_FILE = dpff
    if rewrite
      @CHANGE_PERMISION = true
    else
      @CHANGE_PERMISION = false
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
    $logger.info("default permisions for files #{@DEFAULT_PERMISION_FILE}")
    $logger.info("default permisions for folders #{@DEFAULT_PERMISION_FOLDER}")
    $logger.info("change permision #{@CHANGE_PERMISION}")
    $logger.info("directory to check #{@DEFAULT_DIRECTORY}")
    $logger.info("deep level check #{@LEVEL}")
  end # method initialize

  def run
    $logger.info(@CHANGE_PERMISION)
    #defaultní cesta (vstup)
    Dir.chdir(@DEFAULT_DIRECTORY)

    #první řád složek
    rootFolders = Dir.glob("*/") 

    runScan(rootFolders,@DEFAULT_DIRECTORY)
  end # method run

  #testování příznaku souborů určených v souboru permision.json
  def isPermisionOK(file,permision,dirPath)
    begin
        wr=`stat --format=%a #{dirPath}#{file}`.chomp
      rescue Exception=>e
        $logger.fatal("external program thrown error")
        $logger.fatal(e)
        exit
      else
        if wr==permision
          return true
        else
          $logger.fatal("file #{dirPath}#{file} has #{wr} should be #{permision}")
          if @CHANGE_PERMISION
            $logger.warn("Changing permision of file #{dirPath}#{file} from  #{wr}")
            begin
              `chmod #{permision} #{dirPath}#{file}`
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

  #testování příznaku souborů neurčených v souboru permision.json
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
         when "directory" then default_permision = @DEFAULT_PERMISION_FOLDER
         when "regular file" then default_permision = @DEFAULT_PERMISION_FILE
         else $logger.fatal("Invalid file type #{wd} #{dirPath}#{file}")
      end
  
      if wr==default_permision
        return true
      else
        $logger.fatal("file #{dirPath}#{file} has #{wr} should be #{default_permision}")
        if @CHANGE_PERMISION
          $logger.warn("Changing permision of file #{dirPath}#{file} from  #{wr} to #{default_permision}")
            begin
              `chmod #{default_permision} #{dirPath}#{file}`
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

  #Testování souborů určených v souboru permision.json
  def checkFoldersPermisionFile(dirPath, json, fileHash)
    $logger.info("Check of files in permision.json")
    json.each do |fileName, permision|
      begin
        wd=`stat --format=%F #{dirPath}#{fileName}`.chomp
       rescue Exception=>e
        $logger.fatal("external program thrown error")
        $logger.fatal(e)
        exit
      else
        if wd=="directory"
          Dir.chdir("#{dirPath}#{fileName}")
          ifIsPermisionOK("#{fileName}",permision,dirPath)
          fileHash["#{fileName}"]= true
          
          Dir.glob("**/*").each do |f| 
            ifIsPermisionOK("#{fileName}/#{f}",permision,dirPath)
            fileHash["#{fileName}/#{f}"]= true
          end
        else
          ifIsPermisionOK(fileName,permision,dirPath)
          fileHash["#{fileName}"]= true
        end
      end
    end
    return fileHash 
  end # method checkFoldersPermisionFile

  #opakující se dvojtá podmínka
  def ifIsPermisionOK(fileName,permision,dirPath)
    if !isPermisionOK(fileName,permision,dirPath)
      if !isPermisionOK(fileName,permision,dirPath)
        $logger.fatal("Can't chage permision of the file #{dirPath}#{fileName}")
      end
    end
  end # method ifIsPermisionOK

  #Testování souborů neuvedených v souboru permision.json
  def checkFoldersForDefaultPermision(dirPath, fileHash)
    $logger.info("Check of files outside permision.json")
    fileHash.each do |fileName, isChecked| 
      if !isChecked
        if !isPermisionOKDefault(fileName,dirPath)
          if !isPermisionOKDefault(fileName,dirPath)
            $logger.fatal("Can't chage permision of the file #{dirPath}#{fileName}")
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

      #testovaní existence permisions.json ve složce
      begin
        #otevreni souboru nastaveni
        file = File.open("#{dirPath}permisions.json", &:read)
      rescue Exception=>e
        $logger.fatal(e.message)
        $logger.warn("Skiping folder #{dirPath}")
      else
        json=JSON.parse(file)
        #rutina pro veškerou práci se souborem permisions.json
        checkFoldersPermisionFile(dirPath, json, fileHash)
        #rutina pro veškerou práci se soubory nedefinovanými v permision.json
        checkFoldersForDefaultPermision(dirPath,fileHash)
      end
    end
  end # method runScan
end # class Checker


options = Optparse.parse(ARGV)
puts options
checker = Checker.new(options.default_directory,options.default_file,options.change_permision,options.folder_to_check,options.look_at_level,options.log_file)
checker.run()