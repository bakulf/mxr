#!/usr/bin/ruby
#
# MXR - BSD License - Andrea Marchesini <baku@ippolita.net>
# https://github.com/bakulf/mxr/
#

require 'rubygems'
require 'optparse'
require 'sqlite3'
require 'shellwords'
require 'yaml'

class String
  def is_number?
    true if Float(self) rescue false
  end
end

# the base class
class Bxr

  RESULT    = 'red'
  LINE      = 'green'
  FILE      = 'yellow'
  FILEID    = 'cyan'

  PAGER     = 'less -FRSX'

  DB_FILE   = '.bxr.db'
  CONF_FILE = '.bxr.yml'

  MIN_LEN   = 5

  attr_accessor :inputs
  attr_accessor :retro
  attr_accessor :color
  attr_accessor :vimode
  attr_accessor :max
  attr_accessor :tool
  attr_accessor :db
  attr_accessor :settings
  attr_accessor :showFiles
  attr_accessor :search

  def initialize
    @files = []
    @showFiles = false
  end

  def run
    pre_task

    # no tool:
    if @vimmode == true or @tool.nil?
      @wr = $stdout
      task
      return
    end

    # with a tool
    rd, @wr = IO.pipe
    if Process.fork
      rd.close

      task

      @wr.close
      @wr = nil
      Process.wait
    else
      @wr.close
      $stdin.reopen(rd)

      cmd = @tool.to_s
      cmd += " -p #{@search}" if not @search.nil? and not @search.empty? and
                                 (@tool == 'less' or @tool.start_with? 'less ')
      cmd += " +#{@line}" if @line.is_a? Fixnum and @line != 0

      exec cmd
      exit
    end

    post_task
  end

protected
  def openDb
    @retro = 0

    while true do
      if File.exist? Bxr::CONF_FILE
        config = YAML.load_file Bxr::CONF_FILE
        if config == false or config.nil? or config['bxr'].nil?
          puts "No configuration! Remove ~/.bterm.yml or fix it!"
          exit
        end

        @settings = config['bxr']
        @db = SQLite3::Database.new @settings['db']
        return
      end

      path = Dir.pwd
      break if path == '/' or path.empty?

      Dir.chdir '..'
      @retro += 1
    end

    puts "No db found! Scan the tree!!"
    exit
  end

  def filepath(filename)
    return filename if retro == 0
    path = ''
    retro.times do |r|
      path += '../'
    end
    return path + filename
  end

  def show(title, data, what)
    results = 0

    if @vimode == true
      data.each do |row|
        @files.push({ :file => row[0], :line => row[1]})

        write "#{filepath(row[0])}:#{row[1]}:"
        if row[2] != -1
          write "#{row[2]}:"
        end
        write showline(row[0], row[1], what)

        results += 1
        break if @max.is_a? Fixnum and @max != 0 and results >= @max
      end
    else
      write "#{title}\n"

      prev = nil

      data.each do |row|
        if prev != row[0]
          @files.push({ :file => row[0], :line => 0})
          write "\nFile: #{showFileId}#{color(row[0], Bxr::FILE)}\n"
        end

        @files.push({ :file => row[0], :line => row[1]})
        write "Line: #{showFileId}#{color(row[1].to_s, Bxr::LINE)}"
        write " -> "
        write showline row[0], row[1], what

        prev = row[0]

        results += 1
        break if @max.is_a? Fixnum and @max != 0 and results >= @max
      end
    end
  end

  def showline(path, linenumber, what)
    ret = nil

    if File.exist? path
      File.open path, 'r' do |f|
        while not f.eof? do
          linenumber -= 1
          line = f.readline
          if linenumber == 0
            ret = line
            break
          end
        end

        if not what.nil? and
           not ret.nil? and
           not ret.include? what
          ret = nil
        end
      end
    end

    if ret.nil?
      return "code and bxr out of date\n"
    end

    return ret
  end

  # Write the output
  def write(msg)
    begin
      @wr.write msg unless @wr.nil?
    rescue
    end
  end

  def showFileId
    color "(#{@files.length - 1}) ", Bxr::FILEID if @showFiles == true
  end

  # colorize a string
  def color(str, color, bold = false)
    if @color == true
      str = str.send color
      str = str.bold if bold
    end

    str
  end

  def readtags(line)
    begin
      parts = line.split(/([a-zA-Z0-9_]+)/)
    rescue
      return []
    end

    tags = []
    cn = 0

    parts.each_with_index do |tag, id|
      cn += tag.length
      if id.odd? and tag.length >= MIN_LEN and not tag[0].is_number?
        tags.push({ :tag => tag, :column => cn - tag.length })
      end
    end
    return tags
  end

  # Default pre task does nothing
  def pre_task
  end

  # Default post task does nothing
  def post_task
  end

  def edit_mode
    return if @files.empty?

    begin
      require 'readline'
    rescue
      puts "lib readline is required for mxr in shell mode."
      return
    end

    while line = Readline.readline('bxr> ', true)
      p = Shellwords::shellwords line
      break if p.empty?

      begin
        id = Float(p[0]).to_i
      rescue
        break
      end

      break if id < 0 || id >= @files.length

      editor = ENV['EDITOR']
      if editor.nil? or editor.empty?
        puts "No EDITOR variable found"
        break
      end

      # Bye bye
      cmd = "#{editor} #{@files[id][:file]}"
      cmd += " +#{@files[id][:line]}" if @files[id][:line]

      if not @search.nil? and not @search.empty? and
         [ 'vi', 'vim', 'gvim', 'ex' ].include?(editor)
        cmd += ' -c /' + @search
      end

      exec cmd
    end
  end
end

# scan
class BxrScan < Bxr
  EXTENSIONS = [ '.c', '.cc', '.cpp', '.cxx', '.h', '.hh', '.hpp',
                 '.idl', '.ipdl', '.java', '.js', '.jsm', '.perl', '.php',
                 '.py', '.rb', '.rc', '.sh', '.webidl', '.xml', '.html',
                 '.xul' ]

  def run
    if @inputs.length != 1
      puts "Usage: <path>"
      return
    end

    path = File.expand_path @inputs[0]

    if not File.exist? Bxr::CONF_FILE
      file = File.open Bxr::CONF_FILE, 'w'
      file.write "bxr:\n"
      file.write "  db: " + Bxr::DB_FILE + "\n"
      file.close
    end

    config = YAML.load_file(Bxr::CONF_FILE)
    if config == false or config.nil? or config['bxr'].nil?
      puts "No configuration! Remove .bxr.yml or fix it!"
      return
    end

    if File.exist? config['bxr']['db']
      File.unlink config['bxr']['db']
    end

    @db = SQLite3::Database.new config['bxr']['db']
    @db.execute "CREATE TABLE Bxr ( " +
                "  tag      INTEGER, " +
                "  file     INTEGER, " +
                "  column   INTEGER, " +
                "  line     INTEGER, " +
                "  priority INTEGER  " +
                ")"
    @db.execute "CREATE TABLE Tags ( " +
                "  tag      VARCHAR  " +
                ")"
    @db.execute "CREATE TABLE Files ( " +
                "  path     VARCHAR,  " +
                "  filename VARCHAR,  " +
                "  epoctime INTEGER   " +
                ")"
    @db.execute "CREATE INDEX BxrIndex ON Bxr (tag)"
    @db.execute "CREATE INDEX BxrFileIndex ON Bxr (file)"
    @db.execute "CREATE INDEX TagsIndex ON Tags (tag)"
    @db.execute "CREATE INDEX PriorityIndex ON Bxr (priority)"
    @db.execute "CREATE INDEX FilesIndex ON Files (filename)"
    @db.execute "CREATE INDEX PathIndex ON Files (path)"

    begin
      Dir.chdir(path)
    rescue
      puts "Chdir failed with `#{path}'."
      exit
    end

    @db.transaction do
      scan '.'
    end

  end

  def scan(path)
    Dir.foreach path do |file|
      next if file.start_with? '.'
      fullpath = path + '/' + file

      if File.directory? fullpath
        scan fullpath
      else
        index fullpath
      end
    end
  end

  def index(path)
    return unless EXTENSIONS.include? File.extname(path)

    puts "Scanning: #{color(path, 'yellow')}"

    ln = 0
    basename = File.basename path

    file_tags = {}

    File.open(path, 'r').each_line do |line|
      ln += 1
      tags = readtags line
      next if tags.empty?

      tags.each do |tag|
        file_tags[tag] = [] if not file_tags.include? tag

        file_tags[tag].push({ :column   => tag[:column],
                              :ln       => ln,
                              :priority => priority(tag, line, basename) })
      end
    end

    id = 0
    @db.execute "INSERT INTO Files VALUES(?,?,?)", path, basename, File.mtime(path).to_i
    id = @db.last_insert_row_id

    file_tags.each do |tag, data|
      tagId = nil
      @db.execute "SELECT ROWID FROM Tags WHERE tag = ?", tag[:tag] do |row|
        tagId = row[0]
      end

      if tagId.nil?
        @db.execute "INSERT INTO Tags VALUES(?)", tag[:tag]
        tagId = @db.last_insert_row_id
      end

      data.each do |d|
        @db.execute "INSERT INTO Bxr VALUES(?,?,?,?,?)",
                     tagId, id, d[:column], d[:ln], d[:priority]
      end
    end
  end

  P_IDL_HIGH   = 5
  P_IDL        = 4
  P_CLASS      = 3
  P_IMPL       = 2
  P_NORMAL     = 1
  P_TEST       = 0

  def priority(tag, line, filename)
    extension = File.extname filename

    if [ '.idl', '.webidl' ].include? extension
      return P_IDL_HIGH if line.include? 'interface' and not line.include? ';'
      return P_IDL
    end

    if [ '.ipdl' ].include? extension
      return P_IDL_HIGH if line.include? 'protocol'
      return P_IDL
    end

    if [ '.c', '.cc', '.cpp', '.cxx', '.h', '.hh', '.hpp', '.java' ].include? extension
      return P_IDL if line.include? 'define'
      return P_CLASS if line.include? 'class' and not line.include? ';'
      begin
        return P_IMPL if line.downcase.include? "::#{tag[:tag].downcase}"
      rescue
      end
    end

    if [ '.js', '.jsm' ].include? extension
      return P_CLASS if line.include? 'prototype'
      return P_IMPL if line.include? 'function'
    end

    begin
      return P_TEST if filename.downcase.include? 'test'
    rescue
    end

    return P_NORMAL
  end
end

# Update
class BxrUpdate < BxrScan
  def run
    openDb

    @files = {}
    scan '.'

    filesDb = {}
    @db.execute "SELECT path, epoctime FROM Files" do |row|
      filesDb[row[0]] = row[1]
    end

    # removed files
    @db.transaction do
      removedFiles = filesDb.keys - @files.keys
      removedFiles.each do |file|
        removeFile file
      end

      # new files:
      newFiles = @files.keys - filesDb.keys
      newFiles.each do |file|
        index file
      end

      filesDb.each do |file|
        if @files.include? file[0] and @files[file[0]] != file[1]
          removeFile file[0]
          index file[0]
        end
      end
    end
  end

  def removeFile(file)
    puts "Removing: #{color(file, 'yellow')}"
    @db.execute "DELETE FROM Bxr WHERE file IN (SELECT ROWID FROM Files " +
                "WHERE path = ?)", file
    @db.execute "DELETE FROM Files WHERE path = ?", file
  end

  def scan(path)
    Dir.foreach path do |file|
      next if file.start_with? '.'

      fullpath = path + '/' + file
      next unless File.exists? fullpath

      if File.directory? fullpath
        scan fullpath
      else
        @files[fullpath] = File.mtime(fullpath).to_i
      end
    end
  end
end

# identifier
class BxrIdentifier < Bxr
  def task
    if @inputs.length != 1
      puts "One and Just one argument is needed."
      return false
    end

    openDb

    data = []
    @db.execute "SELECT Files.path, Bxr.line, Bxr.column " +
                "FROM Bxr, Tags, Files " +
                "WHERE Tags.tag = ? AND Bxr.file = Files.ROWID AND Bxr.tag = Tags.ROWID " +
                "ORDER BY Bxr.priority DESC", @inputs[0] do |row|
      data.push row
    end

    show "Result for: #{color(@inputs[0], Bxr::RESULT, true)}", data, @inputs[0]
  end

  def pre_task
    @search = @inputs[0]
  end

  def post_task
    edit_mode if @showFiles
  end
end

class BxrSearch < Bxr
  def task
    if @inputs.length != 1
      puts "One and Just one argument is needed."
      return false
    end

    openDb

    tags = readtags @inputs[0] + " "

    data = []

    if not tags.empty?
      @db.execute "SELECT Files.path, Bxr.line FROM Bxr, Tags, Files " +
                  "WHERE Tags.tag like ? AND Bxr.tag = Tags.ROWID AND Bxr.file = Files.ROWID", "%#{tags[0][:tag]}%" do |row|
        data.push row if showline(row[0], row[1], nil).include? @inputs[0]
      end
    end

    show "Result for: #{color(@inputs[0], Bxr::RESULT, true)}", data, @inputs[0]
  end

  def pre_task
    @search = @inputs[0]
  end

  def post_task
    edit_mode if @showFiles
  end
end

# filenames
class BxrFile < Bxr
  def task
    if @inputs.length != 1
      puts "One and Just one argument is needed."
      return false
    end

    openDb

    data = []
    @db.execute "SELECT DISTINCT path FROM Files " +
                "WHERE filename like ? " +
                "ORDER BY filename", "%#{@inputs[0]}%" do |row|
      data.push row
    end

    show "Result for: #{color(@inputs[0], Bxr::RESULT, true)}", data, @inputs[0]
  end

  def pre_task
    @search = @inputs[0]
  end

  def post_task
    edit_mode if @showFiles
  end

  def show(title, data, what)
    if @vimode == true
      data.each do |row|
        @files.push({ :file => row[0], :line => 0})
        write "#{row[0]}\n"
      end
    else
      write "#{title}\n\n"
      data.each do |row|
        @files.push({ :file => row[0], :line => 0})
        write "File: #{showFileId}#{color(row[0], Bxr::FILE)}\n"
      end
    end
  end
end

# a description of what this app can do:
class Bxr
  LIST = [ { :cmd => 'create',     :class => BxrScan       },
           { :cmd => 'update',     :class => BxrUpdate     },
           { :cmd => 'identifier', :class => BxrIdentifier },
           { :cmd => 'search',     :class => BxrSearch     },
           { :cmd => 'file',       :class => BxrFile       } ]
end

options = {}
opts = OptionParser.new do |opts|
  opts.banner = "Usage: bxr [options] <operation> <something>"
  opts.version = '0.1'

  opts.separator ""
  opts.separator "Operations:"
  opts.separator "- create <path>"
  opts.separator "  Scan a path and create the index file #{Bxr::CONF_FILE}"
  opts.separator "- update"
  opts.separator "  Update the index."
  opts.separator "- identifier <something>"
  opts.separator "  Type the full name of an identifier (a function name, variable name, typedef, etc.) to summarize."
  opts.separator "- search <something>"
  opts.separator "  Search through the source code."
  opts.separator "- file <something>"
  opts.separator "  Search for files (by name)."

  opts.separator ""
  opts.separator "Options:"

  options[:max] = 0
  opts.on('-m', '--max <something>',
          'Set a max number of results shown.') do |something|
    options[:max] = something.to_i
  end

  options[:tool] = Bxr::PAGER
  opts.on('-t', '--tool <tool>',
          "The tool for showing the result. Default: #{Bxr::PAGER}") do |something|
    options[:tool] = something
  end

  opts.on('-T', '--no-tool',
          "No external tool is used for showing the result.") do
    options[:tool] = nil
  end

  options[:color] = false
  opts.on('-c', '--color',
          'Enable the ASCII colors.') do
    begin
      require 'colored'
    rescue
      puts '"colored" gem is required for colored output'
      exit
    end

    options[:color] = true
  end

  options[:vi] = false
  opts.on('-V', '--vi',
          'VIm output.') do
    options[:vi] = true
  end

  options[:edit] = false
  opts.on('-e', '--edit',
          'Offer a shell for fast editing.') do
    options[:edit] = true
  end

  opts.on('-h', '--help', 'Display this screen.') do
    puts opts
    exit
  end

  opts.separator ""
  opts.separator "BSD license - Andrea Marchesini <baku@ippolita.net>"
  opts.separator ""
end

# I don't want to show exceptions if the params are wrong:
begin
  opts.parse!
rescue
  puts opts
  exit
end

task = nil

# task selection
op = nil
Bxr::LIST.each do |c|
  if c[:cmd].start_with? ARGV[0]
    op = c
    break
  end
end

if op.nil?
  puts opts
  exit
end

task = op[:class].new
ARGV.shift
task.inputs = ARGV

task.color     = options[:color]
task.vimode    = options[:vi]
task.max       = options[:max]
task.tool      = options[:tool]
task.showFiles = options[:edit]

task.run
