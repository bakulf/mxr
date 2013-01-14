#!/usr/bin/ruby
#
# MXR - BSD License - Andrea Marchesini <baku@ippolita.net>
# https://github.com/bakulf/mxr/
#

require 'rubygems'
require 'optparse'
require 'sqlite3'

class String
  def is_number?
    true if Float(self) rescue false
  end
end

# the base class
class Bxr

  RESULT  = 'red'
  LINE    = 'green'
  FILE    = 'yellow'
  FILEID  = 'cyan'

  PAGER   = 'less -FRSX'

  DB_FILE = '.bxr.db'

  MIN_LEN = 5

  attr_accessor :input
  attr_accessor :retro
  attr_accessor :color
  attr_accessor :vimode
  attr_accessor :line
  attr_accessor :max
  attr_accessor :tool
  attr_accessor :db

  def initialize
  end

  def run

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
      cmd += " +#{@line}" if @line.is_a? Fixnum and @line != 0

      exec cmd
      exit
    end
  end

protected
  def openDb
    @retro = 0

    while true do
      if File.exist? Bxr::DB_FILE
        @db = SQLite3::Database.new Bxr::DB_FILE
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

  def show(title, data)
    results = 0

    if @vimode == true
      data.each do |row|
        write "#{filepath(row[0])}:#{row[1]}:"
        if row[2] != -1
          write "#{row[2]}:"
        end
        write showline(row[0], row[1])

        results += 1
        break if @max.is_a? Fixnum and @max != 0 and results >= @max
      end
    else
      write "#{title}\n"

      prev = nil

      data.each do |row|
        write "\nFile: #{color(row[0], Bxr::FILE)}\n" if prev != row[0]
        write "Line: #{color(row[1].to_s, Bxr::LINE)}"
        write " -> "
        write showline row[0], row[1]

        prev = row[0]

        results += 1
        break if @max.is_a? Fixnum and @max != 0 and results >= @max
      end
    end
  end

  def showline(path, linenumber)
    File.open path, 'r' do |f|
      while not f.eof? do
        linenumber -= 1
        line = f.readline
        return line if linenumber == 0
      end
      "\n"
    end
  end

  # Write the output
  def write(msg)
    begin
      @wr.write msg unless @wr.nil?
    rescue
    end
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
    tags = []
    tag = []

    cn = 0
    line.each_char do |c|
      cn += 1
      if (c >= 'a' and c <= 'z') or
         (c >= 'A' and c <= 'Z') or
         (c >= '0' and c <= '9') or
         c == '_'
        tag.push c
      elsif not tag.empty?
        if tag.length >= MIN_LEN and not tag[0].is_number?
          tags.push({ :tag => tag.join, :column => cn - tag.length})
        end
        tag = []
      end
    end
    return tags
  end

end

# scan
class BxrScan < Bxr
  EXTENSIONS = [ '.c', '.cc', '.cpp', '.cxx', '.h', '.hh', '.hpp',
                 '.idl', '.ipdl', '.java', '.js', 'jsm', '.perl', '.php', '.py',
                 '.rb', '.rc', '.sh', '.webidl', '.xml', '.html', '.xul' ]

  def run
    if @input.nil?
      puts "No input, no party"
      return false
    end

    begin
      Dir.chdir(@input)
    rescue
      puts "Chdir failed with `#{@input}'."
      exit
    end

    if File.exist? Bxr::DB_FILE
      File.unlink Bxr::DB_FILE
    end

    @db = SQLite3::Database.new Bxr::DB_FILE
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
                "  filename VARCHAR   " +
                ")"
    @db.execute "CREATE INDEX BxrIndex ON Bxr (tag)"
    @db.execute "CREATE INDEX TagsIndex ON Tags (tag)"
    @db.execute "CREATE INDEX PriorityIndex ON Bxr (priority)"
    @db.execute "CREATE INDEX FilesIndex ON Files (filename)"

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
    id = 0
    basename = File.basename path

    File.open path, 'r' do |f|
      while not f.eof? do
        ln += 1
        line = f.readline
        tags = readtags line
        next if tags.empty?

        if id == 0
          @db.execute "INSERT INTO Files VALUES(?,?)",
                       path, basename
          id = @db.last_insert_row_id
        end

        tags.each do |tag|
          tagId = nil
          @db.execute "SELECT ROWID FROM Tags WHERE tag = ?", tag[:tag] do |row|
            tagId = row[0]
          end
          if tagId.nil?
            @db.execute "INSERT INTO Tags VALUES(?)", tag[:tag]
            tagId = @db.last_insert_row_id
          end

          @db.execute "INSERT INTO Bxr VALUES(?,?,?,?,?)",
                      tagId, id, tag[:column], ln, priority(tag, line, basename)
        end
      end
    end
  end

  P_IDL_HIGH   = 5
  P_IDL        = 4
  P_CLASS      = 3
  P_IMPL       = 2
  P_NORMAL     = 1

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
      return P_CLASS if line.include? 'class' and not line.include? ';'
      begin
        return P_IMPL if line.downcase.include? "#{tag[:tag].downcase}::#{tag[:tag].downcase}"
      rescue
      end
    end

    if [ '.js', '.jsm' ].include? extension
      return P_CLASS if line.include? 'prototype'
      return P_IMPL if line.include? 'function'
    end

    return P_NORMAL
  end
end

# identifier
class BxrIdentifier < Bxr
  def task
    if @input.nil?
      puts "No input, no party"
      return false
    end

    openDb

    data = []
    @db.execute "SELECT Files.path, Bxr.line, Bxr.column " +
                "FROM Bxr, Tags, Files " +
                "WHERE Tags.tag = ? AND Bxr.file = Files.ROWID AND Bxr.tag = Tags.ROWID " +
                "ORDER BY Bxr.priority DESC", @input do |row|
      data.push row
    end

    show "Result for: #{color(@input, Bxr::RESULT, true)}", data
  end
end

class BxrSearch < Bxr
  def task
    if @input.nil?
      puts "No input, no party"
      return false
    end

    openDb

    tags = readtags @input + " "

    data = []

    if not tags.empty?
      @db.execute "SELECT Files.path, Bxr.line FROM Bxr, Tags, Files " +
                  "WHERE Tags.tag like ? AND Bxr.tag = Tags.ROWID AND Bxr.file = Files.ROWID", "%#{tags[0][:tag]}%" do |row|
        data.push row if showline(row[0], row[1]).include? @input
      end
    end

    show "Result for: #{color(@input, Bxr::RESULT, true)}", data
  end
end

# filenames
class BxrFile < Bxr
  def task
    if @input.nil?
      puts "No input, no party"
      return false
    end

    openDb

    data = []
    @db.execute "SELECT DISTINCT filename FROM Files " +
                "WHERE filename like ? " +
                "ORDER BY filename", "%#{@input}%" do |row|
      data.push row
    end

    show "Result for: #{color(@input, Bxr::RESULT, true)}", data
  end

  def show(title, data)
    if @vimode == true
      data.each do |row|
        write "#{row[0]}\n"
      end
    else
      write "#{title}\n\n"
      data.each do |row|
        write "File: #{color(row[0], Bxr::FILE)}\n"
      end
    end
  end
end

# a description of what this app can do:
class Bxr
  LIST = [ { :cmd => 'create',     :class => BxrScan       },
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
  opts.separator "  Scan a path and create the index file #{Bxr::DB_FILE}"
  opts.separator "- identifier <something>"
  opts.separator "  Type the full name of an identifier (a function name, variable name, typedef, etc.) to summarize. Matches are case-sensitive."
  opts.separator "- search <something>"
  opts.separator "  Free-text search through the source code, including comments."
  opts.separator "- file <something>"
  opts.separator "  Search for files (by name) using regular expressions."

  opts.separator ""
  opts.separator "Options:"

  options[:max] = 0
  opts.on('-m', '--max <something>',
          'Set a max number of results shown.') do |something|
    options[:max] = something.to_i
  end

  options[:line] = 0
  opts.on('-l', '--line <something>',
          'Jump to this line.') do |something|
    options[:line] = something.to_i
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
if ARGV.length == 2
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
  task.input = ARGV[1]

# error
else
  puts opts
  exit
end

task.color  = options[:color]
task.vimode = options[:vi]
task.max    = options[:max]
task.line   = options[:line]
task.tool   = options[:tool]

task.run
