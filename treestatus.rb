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
  elsif status == 'opened'
    status = status.green
  else
    status = status.yellow
  end

  puts "#{title}: #{status.bold}"
end

uri = URI('https://treestatus.mozilla.org/?format=json')

res = Net::HTTP.get_response(uri)
if not res.is_a?(Net::HTTPSuccess)
  puts "Something went wrong."
  exit
end

json = JSON.parse res.body

printstatus json['try'], 'try' if json.include? 'try'
printstatus json['mozilla-inbound'], 'm-i' if json.include? 'mozilla-inbound'
