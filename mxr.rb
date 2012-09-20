#!/usr/bin/ruby
#
# MXR - BSD License - Andrea Marchesini <baku@ippolita.net>
# https://github.com/bakulf/mxr/
#

require 'rubygems'
require 'hpricot'
require 'optparse'
require 'open-uri'
require 'shellwords'
require 'cgi'

# <hack>
require 'openssl'
module OpenSSL
  module SSL
    remove_const :VERIFY_PEER
  end
end
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE
# </hack>

# the base class
class Mxr

  RESULT = 'red'
  LINE   = 'green'
  FILE   = 'yellow'
  FILEID = 'cyan'
  PAGER  = 'less -FRSX'

  DEFAULT_TREE = 'mozilla-central'

  attr_accessor :url
  attr_accessor :input
  attr_accessor :tree
  attr_accessor :path
  attr_accessor :color
  attr_accessor :line
  attr_accessor :tool
  attr_accessor :files
  attr_accessor :showFiles

  def initialize
    @files = []
    @showFiles = false
  end

  def run
    # the main operation
    if main == false
      return
    end

    # no tool:
    if @tool.nil?
      @wr = $stdout
      print
      return
    end

    # with a tool
    rd, @wr = IO.pipe
    if Process.fork
      rd.close

      # print the output
      print

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
  def showFileId
    color "(#{@files.length - 1}) ", Mxr::FILEID if @showFiles == true
  end

  # colorize a string
  def color(str, color, bold = false)
    if @color == true
      str = str.send color
      str = str.bold if bold
    end

    str
  end

  # Write the output
  def write(msg)
    begin
      @wr.write msg unless @wr.nil?
    rescue
    end
  end

  # helper:
  def getPath
    return '' if @path.nil?
    return @path + '/' unless @path.end_with? '/'
    return @path
  end

  # horrible MXR html parser:
  def show(filename, ul)
    @files.push({ :file => filename, :line => 0})
    write "\nFile: #{showFileId}#{color(getPath + filename, Mxr::FILE)}\n"

    return unless ul.children.is_a? Array
    ul.children.each do |info|
      next unless info.is_a? Hpricot::Elem
      next unless info.name  == 'li'

      line = info.at('a').inner_html.split(' ')[1]
      @files.push({ :file => filename, :line => line})

      write "Line: #{showFileId}#{color(line.to_s, Mxr::LINE)}"
      write " -> "
      text = showText(info).gsub("\n", ' ')
      pos = text.index ' -- '
      if pos.nil?
        write text
      else
        write text[(pos+4)..-1]
      end
      write "\n"
    end
  end

  # The open-uri + hpricot is executed in a separated thread:
  def getContent
    doc = nil
    th = Thread.new do
      begin
        doc = open(@url) do |f|
          Hpricot(f)
        end
      rescue
        doc = false
      end
    end

    cursor = '|/-\\'
    i = 0
    while doc.nil?
      STDOUT.write "Retriving data #{cursor[i%cursor.length].chr}\r"
      STDOUT.flush
      sleep 0.1
      i += 1
    end

    th.join
    @doc = doc

    if @doc == false
      puts "The network or the mxr website seem down."
      return false
    end

    return true
  end

private
  def showText(elem)
    text = ''
    if elem.is_a? Hpricot::Text
      text += elem.to_s
    elsif elem.is_a? Hpricot::Elem and
          elem.children.is_a? Array and
          elem.name != 'style'
      elem.children.each do |e|
        text += showText e
      end
    end

    text
  end
end

# identifier
class MxrIdentifier < Mxr
  def main
    if @input.nil?
      puts "No input, no party"
      return false
    end

    @url = "https://mxr.mozilla.org/#{@tree}/ident?i=#{CGI.escape(@input)}&tree=#{CGI.escape(@tree)}"
    return getContent
  end

  def print
    write "Result for: #{color(@doc.at('//h1').inner_html, Mxr::RESULT, true)}\n"

    @doc.search('/html/body/ul').each do |ul|
      next unless ul.children.is_a? Array
      ul.children.each do |li|
        next unless li.is_a? Hpricot::Elem and
                    li.name == 'li' and
                    li.children.is_a? Array

        filename = li.at('a').inner_html
        li.children.each do |ul|
          next unless ul.is_a? Hpricot::Elem
          next unless ul.name == 'ul'
          show filename, ul
        end
      end
    end
  end
end

# full-text search
class MxrSearch < Mxr
  def main
    if @input.nil?
      puts "No input, no party"
      return false
    end

    @url = "https://mxr.mozilla.org/#{@tree}/search?string=#{CGI.escape(@input)}"
    return getContent
  end

  def print
    write "Result for: #{color(@doc.at('//h1').inner_html, Mxr::RESULT, true)}\n"

    newBlock = true
    filename = nil

    @doc.search('/html/body/*').each do |e|
      next unless e.is_a? Hpricot::Elem

      if e.name == 'a'
        next if e.attributes['href'].nil?
        next unless e.attributes['href'].include? @tree
        next unless e.attributes['href'].include? 'source'

        if newBlock == true
          filename = []
          newBlock = false
        else
        end
        filename.push e.inner_html if e.inner_html != '/'

      elsif e.name == 'ul'
        if newBlock == false
          newBlock = true
          show filename.join('/'), e
        end
      end
    end
  end
end

# filenames
class MxrFile < Mxr
  def main
    if @input.nil?
      puts "No input, no party"
      return false
    end

    @url = "https://mxr.mozilla.org/#{@tree}/find?string=#{CGI.escape(@input)}"
    return getContent
  end

  def print
    write "Result for: #{color(@input, Mxr::RESULT, true)}\n\n"

    @doc.search('/html/body/span').each do |span|
      next unless span.children.is_a? Array

      filename = []
      span.children.each do |e|
        next unless e.is_a? Hpricot::Elem
        next unless e.name == 'a'
        next if e.attributes['href'].nil?
        next unless e.attributes['href'].include? @tree
        next unless e.attributes['href'].include? 'source'

        filename.push e.inner_html if e.inner_html != '/'
      end

      filename = filename.join('/')
      @files.push({ :file => filename, :line => 0})
      write "File: #{showFileId}#{color(getPath + filename, Mxr::FILE)}\n"
    end
  end
end

# browse a single file
class MxrBrowse < Mxr
  def run
    # a number
    if @input.to_i.to_s == @input
      file = @files[@input.to_i]
      if file.nil?
        puts "FileId unknown\n"
        return
      end

      @input = file[:file]
      @line = file[:line].to_i
    end

    if @input.nil? or @input.empty?
      puts "Nothing to show"
      return
    end

    if not @input.include? '/'
      puts "#{input} doesn't seem a full path."
      return
    end

    super
  end

  def main
    if @input.nil?
      puts "No input, no party"
      return false
    end

    @url = "https://mxr.mozilla.org/#{@tree}/source/#{@input}"
    return getContent
  end

  def print
    @doc.search('/html/body/pre').each do |pre|
      write showText(pre)
    end
  end

private
  def showText(elem)
    return super if @color == false

    text = ''
    if elem.is_a? Hpricot::Text
      text += elem.to_s
    elsif elem.is_a? Hpricot::Elem and
          elem.children.is_a? Array and
          elem.name != 'style'
      stext = ''
      elem.children.each do |e|
        stext += showText e
      end

      if not elem.attributes.nil? and
         not elem.attributes['class'].nil?
        if elem.attributes['class'] == 'c'
          stext = stext.cyan
        elsif elem.attributes['class'] == 'v'
          stext = stext.magenta
        elsif elem.attributes['class'] == 'i'
          stext = stext.green
        elsif elem.attributes['class'] == 'd'
          stext = stext.yellow
        end
      end

      text += stext
    end

    text
  end
end

# A simple shell:
class MxrShell < Mxr

  def run
    begin
      require 'readline'
    rescue
      puts "lib readline is required for mxr in shell mode."
      exit
    end

    cmds = []
    Mxr::LIST.each do |c| cmds.push c[:cmd] end
    cmds += [ 'help', 'quit' ]
    comp = proc { |s| cmds.grep( /^#{Regexp.escape(s)}/ ) }

    Readline.completion_append_character = " "
    Readline.completion_proc = comp

    history_p = []
    history_c = nil
    history_n = []

    while line = Readline.readline('mxr> ', true)
      p = Shellwords::shellwords line
      next if p.empty?

      # quit:
      break if 'quit'.start_with? p[0]

      # prev:
      pn = false
      if 'prev'.start_with? p[0]
        if history_p.empty?
          puts "No prev command"
          next
        end

        p = history_p.pop
        history_n.push history_c if not history_c.nil?
        history_c = p
        pn = true
      end

      # next
      if 'next'.start_with? p[0]
        if history_n.empty?
          puts "No next command"
          next
        end

        p = history_n.pop
        history_p.push history_c if not history_c.nil?
        history_c = p
        pn = true
      end

      if 'help'.start_with? p[0]
        if pn == false
          history_n = []
          history_p.push history_c if not history_c.nil?
          history_c = p
        end

        help
        next
      end

      # check the command:
      op = nil
      Mxr::LIST.each do |c|
        if c[:cmd].start_with? p[0]
          op = c
        end
      end

      if op.nil?
        puts "#{p[0]}: command not found"
      else
        # history: prev/next
        if pn == false
          history_n = []
          history_p.push history_c if not history_c.nil?
          history_c = p
        end

        cmd = op[:class].new
        cmd.tree  = @tree
        cmd.path  = @path
        cmd.color = @color
        cmd.tool  = @tool
        cmd.showFiles = true
        cmd.files = @files if op[:withFiles]
        cmd.input = p[1]
        cmd.run
        @files = cmd.files
      end
    end
  end

  def help
    puts "#{color('identifier')} <something>"
    puts "  Type the full name of an identifier (a function name, variable name, typedef, etc.) to summarize. Matches are case-sensitive."
    puts "#{color('search')} <something>"
    puts "  Free-text search through the source code, including comments."
    puts "#{color('file')} <something>"
    puts "  Search for files (by name) using regular expressions."
    puts "#{color('browse')} <something>"
    puts "  Show a file."
    puts "#{color('prev')}"
    puts "  Exec the previous command."
    puts "#{color('next')}"
    puts "  Exec the following command if 'prev' has been used."
    puts "#{color('quit')}"
    puts "  Close this shell."
    puts "#{color('help')}"
    puts "  Show this help."
  end

  def color(str)
   if @color == true
     # just for fun:
     colors = Colored::COLORS.keys.dup
     colors.delete 'black'

     str = super str, colors.shuffle[0]
   else
     str
   end
  end
end

# a description of what this app can do:
class Mxr
  LIST = [ { :cmd => 'identifier', :class => MxrIdentifier, :withFiles => false },
           { :cmd => 'search',     :class => MxrSearch,     :withFiles => false },
           { :cmd => 'file',       :class => MxrFile,       :withFiles => false },
           { :cmd => 'browse',     :class => MxrBrowse,     :withFiles => true  } ]
end

options = {}
opts = OptionParser.new do |opts|
  opts.banner = "Usage: mxr [options] <operation> <something>"
  opts.version = '0.1'

  opts.separator ""
  opts.separator "Operations:"
  opts.separator "- identifier <something>"
  opts.separator "  Type the full name of an identifier (a function name, variable name, typedef, etc.) to summarize. Matches are case-sensitive."
  opts.separator "- search <something>"
  opts.separator "  Free-text search through the source code, including comments."
  opts.separator "- file <something>"
  opts.separator "  Search for files (by name) using regular expressions."
  opts.separator "- browse <something>"
  opts.separator "  Show a file."

  opts.separator ""
  opts.separator "Without any operation mxr starts in shell mode."
  opts.separator ""
  opts.separator "Options:"

  options[:line] = 0
  opts.on('-l', '--line <something>',
          'Jump to this line.') do |something|
    options[:line] = something.to_i
  end

  options[:tree] =  Mxr::DEFAULT_TREE
  opts.on('-t', '--tree <something>',
          "Set a tree (default: #{Mxr::DEFAULT_TREE}).") do |something|
    options[:tree] = something
  end

  options[:tool] = Mxr::PAGER
  opts.on('-t', '--tool <tool>',
          "The tool for showing the result. Default: #{Mxr::PAGER}") do |something|
    options[:tool] = something
  end

  opts.on('-T', '--no-tool',
          "No external tool is used for showing the result.") do
    options[:tool] = nil
  end

  options[:path] = nil
  opts.on('-p', '--path <local/path/for/the/repo>',
          'The local path for the repository. This will be used to show the filenames.') do |something|
    options[:path] = something
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

# 2 arguments: good - single operation
if ARGV.length == 2
  op = nil
  Mxr::LIST.each do |c|
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

# no arguments: good - shell
elsif ARGV.empty?
  task = MxrShell.new

# error
else
  puts opts
  exit
end

task.tree = options[:tree]
task.path = options[:path]
task.color = options[:color]
task.line = options[:line]
task.tool = options[:tool]

task.run
