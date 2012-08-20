#!/usr/bin/ruby
#
# TRY - BSD License - Andrea Marchesini <baku@ippolita.net>
# https://github.com/bakulf/try/
#

require 'rubygems'
require 'optparse'
require 'open-uri'
require 'json'

# <hack>
require 'openssl'
module OpenSSL
  module SSL
    remove_const :VERIFY_PEER
  end
end
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE
# </hack>

class Try
  DEFAULT_MAXREQUESTS = 20

  C_USER   = 'cyan'
  C_DATE   = 'yellow'
  C_URL    = 'blue'

  C_OK        = 'green'
  C_BROKEN    = 'yellow'
  C_FAILED    = 'red'
  C_RETRY     = 'blue'
  C_EXCEPTION = 'cyan'

  attr_accessor :url
  attr_accessor :email
  attr_accessor :number
  attr_accessor :maxRequests
  attr_accessor :last
  attr_accessor :color

  def run
    @request = 0

    while @number > 0 do
      break if @request == @maxRequests

      v = runTry
      break if v == false
      @number -= v

      @request += 1
    end
  end

private
  def runTry
    doc = getContent
    if doc == false
      putsFill "The network or the mxr website seem down."
      return false
    end

    pushes = []
    doc.each do |k,v|
      last = v['changesets'].last
      next if last.nil?
      rev = last['node'][0...12]

      obj = { :id         => k.to_i,
              :rev        => rev,
              :user       => v['user'],
              :date       => v['date'].to_i,
              :changesets => v['changesets'] }
      pushes.push obj
    end

    pushes.sort! do |a,b|
      a[:id] <=> b[:id]
    end

    pushes.reverse!
    @last = pushes.last[:id]

    n = 0
    pushes.each do |p|
      if @email.nil? or @email == p[:user]

        putsFill "#{color(p[:user], Try::C_USER)} - #{color(Time.at(p[:date]).to_s, Try::C_DATE)}"
        putsFill "  Url: #{color("https://tbpl.mozilla.org/?tree=Try&rev=#{p[:rev]}", Try::C_URL)}"

	p[:changesets].each do |cs|
          putsFill "  " + cs['desc'].gsub("\n", " ")
	end

        printRevStatus getRev(p)

	putsFill

        n += 1
      end
    end

    return n
  end

  def printRevStatus(data)
    if data == false
      putsFill "  Status: #{color("Error retrieving data.", Try::C_FAILED)}"
    end

    status = { :success => 0, :broken => 0, :failed => 0, :retry => 0, :exception => 0 }

    data.each do |d|
      if d['result'] == 'success'
        status[:success] += 1
      elsif d['result'] == 'testfailed'
        status[:broken] += 1
      elsif d['result'] == 'busted'
        status[:failed] += 1
      elsif d['result'] == 'retry'
        status[:retry] += 1
      elsif d['result'] == 'exception'
        status[:exception] += 1
      else
        puts "UNSUPPORTED RESULT: " + d['result']
      end
    end

    report = []
    report.push "success(#{color(status[:success].to_s, Try::C_OK)})"            if status[:success] > 0
    report.push "broken(#{color(status[:broken].to_s, Try::C_BROKEN)})"          if status[:broken] > 0
    report.push "failed(#{color(status[:failed].to_s, Try::C_FAILED)})"          if status[:failed] > 0
    report.push "retry(#{color(status[:retry].to_s, Try::C_RETRY)})"             if status[:retry] > 0
    report.push "exception(#{color(status[:exception].to_s, Try::C_EXCEPTION)})" if status[:exception] > 0

    putsFill "  Status: #{report.join(' ')}"
  end

  # colorize a string
  def color(str, color, bold = false)
    if @color == true
      str = str.send color
      str = str.bold if bold
    end

    str
  end

  def getRev(data)
    url = "https://tbpl.mozilla.org/php/getRevisionBuilds.php?branch=try&rev=#{data[:rev]}"
    doc = nil
    th = Thread.new do
      begin
        doc = open(url) do |f|
          JSON.parse(f.read)
        end
      rescue
        doc = false
      end
    end

    cursor = '|/-\\'
    i = 0
    while doc.nil?
      STDOUT.write "Retriving data for revision #{cursor[i%cursor.length].chr}\r"
      STDOUT.flush
      sleep 0.1
      i += 1
    end

    th.join

    return doc
  end

  # The open-uri + json is executed in a separated thread:
  def getContent
    url = "https://hg.mozilla.org/try/json-pushes?full=1"
    if not @last.nil?
      url += "&startID=#{@last-11}&endID=#{@last-1}"
    else
      url += "&maxhours=24"
    end

    doc = nil
    th = Thread.new do
      begin
        doc = open(url) do |f|
          JSON.parse(f.read)
        end
      rescue
        doc = false
      end
    end

    cursor = '|/-\\'
    i = 0
    while doc.nil?
      STDOUT.write "Retriving data (request #{@request+1}) #{cursor[i%cursor.length].chr}\r"
      STDOUT.flush
      sleep 0.1
      i += 1
    end

    th.join

    return doc
  end

  def putsFill(what = '')
    print what
    (what.length...80).each do print ' ' end
    print "\n"
  end
end

options = {}
opts = OptionParser.new do |opts|
  opts.banner = "Usage: try [options]"
  opts.version = '0.1'

  opts.separator ""
  opts.separator "Options:"

  options[:number] = 1
  opts.on('-n', '--number <number>', 'Show #pushes') do |number|
    options[:number] = number.to_i
  end

  options[:maxRequests] = Try::DEFAULT_MAXREQUESTS
  opts.on('-M', '--maxRequests <maxRequests>',
          "Max number of requests. (Default: #{Try::DEFAULT_MAXREQUESTS})") do |maxRequests|
    options[:maxRequests] = maxRequests.to_i
  end

  options[:email] = nil
  opts.on('-e', '--email <emailAddress>', 'Set the email to be shown') do |email|
    options[:email] = email
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

try = Try.new

try.email = options[:email]
try.number = options[:number]
try.maxRequests = options[:maxRequests]
try.color = options[:color]

try.run
