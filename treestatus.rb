#!/usr/bin/ruby
#
# MXR - BSD License - Andrea Marchesini <baku@ippolita.net>
# https://github.com/bakulf/mxr/
#

require 'net/http'
require 'json'
require 'colored'

def printstatus(what, title)
  status = what['status']
  if status == 'closed'
    status = status.red
  elsif status == 'open'
    status = status.green
  else
    status = status.yellow
  end

  puts "#{title}: #{status.bold}"
end

uri = URI('https://treestatus.mozilla-releng.net/trees?format=json')

res = Net::HTTP.get_response(uri)
if not res.is_a?(Net::HTTPSuccess)
  puts "Something went wrong."
  exit
end

json = JSON.parse res.body

if json.nil? or not json.include? 'result'
  puts "Something went wrong (2)."
  exit
end

printstatus json['result']['try'], 'try' if json['result'].include? 'try'
printstatus json['result']['mozilla-inbound'], 'm-i' if json['result'].include? 'mozilla-inbound'
