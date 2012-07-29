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
  CMD    = 'cyan'
  PAGER  = 'less -FRSX'

  DEFAULT_TREE = 'mozilla-central'

  attr_accessor :url
  attr_accessor :input
  attr_accessor :tree
  attr_accessor :path
  attr_accessor :color
  attr_accessor :line
  attr_accessor :tool

  def run
    # no tool:
    if @tool.nil?
      @wr = $stdout
      main
      return
    end

    # with a tool
    rd, @wr = IO.pipe

    if Process.fork
      trap("INT") do
        puts "Write 'q' to exit"
      end

      rd.close

      # this does the magic
      main

      @wr.close
      Process.wait
    else
      @wr.close
      $stdin.reopen(rd)

      cmd = @tool.to_s
      cmd += " +#{@line}" if @line.is_a? Fixnum and @line != 0

      exec cmd

      @wr.close
      @wr = nil
      exit
    end
  end

protected
  # colorize a string
  def color(str, color, bold = false)
    return str if @color == false

    str = str.send color
    str = str.bold if bold
    str
  end

  # Write the output
  def write(msg)
    return if @wr.nil?

    begin
      @wr.write msg
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
    write "\nFile: #{color(getPath + filename, Mxr::FILE)}\n"
    write "Browse: #{color("mxr -b " + filename + cmdParams(true), Mxr::CMD)}\n"

    return unless ul.children.is_a? Array
    ul.children.each do |info|
      next unless info.is_a? Hpricot::Elem
      next unless info.name  == 'li'
      write "Line: #{color(info.at('a').inner_html.split(' ')[1].to_s, Mxr::LINE)}"
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
    Thread.new do
      doc = open(@url) do |f|
        Hpricot(f)
      end
    end

    cursor = '|/-\\'
    i = 0
    while doc.nil?
      print "Retriving data #{cursor[i%cursor.length].chr}\r"
      STDOUT.flush
      sleep 0.1
      i += 1
    end

    doc
  end

  # List of params for the Browse:
  def cmdParams(line = false)
    params=[]
    params.push '-c' if @color
    params.push "-t #{Shellwords.escape(@tree)}" unless @tree.nil? or @tree == Mxr::DEFAULT_TREE
    params.push "-l <line>" if line == true
    return " #{params.join(' ')}"
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
    @url = "https://mxr.mozilla.org/#{@tree}/ident?i=#{CGI.escape(@input)}&tree=#{CGI.escape(@tree)}"
    doc = getContent

    write "Result for: #{color(doc.at('//h1').inner_html, Mxr::RESULT, true)}\n"

    doc.search('/html/body/ul').each do |ul|
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
    @url = "https://mxr.mozilla.org/#{@tree}/search?string=#{CGI.escape(@input)}"
    doc = getContent

    write "Result for: #{color(doc.at('//h1').inner_html, Mxr::RESULT, true)}\n"

    newBlock = true
    filename = nil

    doc.search('/html/body/*').each do |e|
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
    @url = "https://mxr.mozilla.org/#{@tree}/find?string=#{CGI.escape(@input)}"
    doc = getContent

    write "Result for: #{color(@input, Mxr::RESULT, true)}\n\n"

    doc.search('/html/body/span').each do |span|
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

      write "File: #{color(getPath + filename.join('/'), Mxr::FILE)}\n"
      write "Browse: #{color("mxr -b " + filename.join('/') + cmdParams, Mxr::CMD)}\n\n"
    end
  end
end

# browse a single file
class MxrBrowse < Mxr
  def main
    @url = "https://mxr.mozilla.org/#{@tree}/source/#{@input}"
    doc = getContent

    doc.search('/html/body/pre').each do |pre|
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
  LIST = [ { :cmd => 'identifier', :class => MxrIdentifier },
           { :cmd => 'search',     :class => MxrSearch     },
           { :cmd => 'file',       :class => MxrFile       },
           { :cmd => 'browse',     :class => MxrBrowse     } ]

  def run
    require 'readline'

    cmds = []
    LIST.each do |c| cmds.push c[:cmd] end
    comp = proc { |s| cmds.grep( /^#{Regexp.escape(s)}/ ) }

    Readline.completion_append_character = " "
    Readline.completion_proc = comp

    while line = Readline.readline('mxr> ', true)
      p = line.split
      next if p.empty?

      break if 'quit'.start_with? p[0]

      cmd = nil
      LIST.each do |c|
        if c[:cmd].start_with? p[0]
          cmd = c[:class]
        end
      end

      if cmd.nil?
        puts p[0] + ': command not found'
      else
        cmd = cmd.new
        cmd.tree  = @tree
        cmd.path  = @path
        cmd.color = @color
        cmd.tool  = @tool
        cmd.input = p[1]
        cmd.run
      end
    end
  end
end

options = {}
opts = OptionParser.new do |opts|
  opts.banner = "Usage: mxr [options]"
  opts.version = '0.1'

  opts.separator ""
  opts.separator "Options:"

  options[:identifier] = nil
  opts.on('-i', '--identifier <something>',
          'Type the full name of an identifier (a function name, variable name, typedef, etc.) to summarize. Matches are case-sensitive.') do |something|
    options[:identifier] = something
  end

  options[:search] = nil
  opts.on('-s', '--search <something>',
          'Free-text search through the source code, including comments.') do |something|
    options[:search] = something
  end

  options[:file] = nil
  opts.on('-f', '--file <something>',
          'Search for files (by name) using regular expressions.') do |something|
    options[:file] = something
  end

  options[:browse] = nil
  opts.on('-b', '--browse <something>',
          'Show a file.') do |something|
    options[:browse] = something
  end

  opts.separator ""
  opts.separator "Common options:"

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
    require 'colored'
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

# Let's decide what we want to do:
task = nil
if not options[:identifier].nil?
  task = MxrIdentifier.new
  task.input = options[:identifier]

elsif not options[:search].nil?
  task = MxrSearch.new
  task.input = options[:search]

elsif not options[:file].nil?
  task = MxrFile.new
  task.input = options[:file]

elsif not options[:browse].nil?
  task = MxrBrowse.new
  task.input = options[:browse]

else
  task = MxrShell.new
end

task.tree = options[:tree]
task.path = options[:path]
task.color = options[:color]
task.line = options[:line]
task.tool = options[:tool]

task.run
