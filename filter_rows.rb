#!/usr/bin/env ruby
# filters rows from the second argument by SID that appear in the first argument
require 'json'
require 'set'

sids = Set.new

File.open(ARGV[0], 'r') do |f|
  f.each_line do |line|
    sid = JSON.parse(line)['sid']
    next if sid == nil || sid == ''

    sids << sid
  end
end

File.open(ARGV[1], 'r') do |f|
  f.each_line do |line|
    next unless sids.include?(JSON.parse(line)['sid'])

    puts line
  end
end
