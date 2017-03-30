#!/usr/bin/env ruby
# usage: ./$0 tmp/before.json tmp/after.json
require 'json'
require 'date'

before_by_sid = {}
stats = {
  total_changed: 0,
  total_moved_earlier: 0,
  pending_to_calculated: 0,
  calculated_to_pending: 0,
  date_moved_later: 0,
  date_moved_earlier_less_than_14_days: 0,
  date_moved_earlier_less_than_90_days: 0,
  date_moved_earlier_less_than_180_days: 0,
  date_moved_earlier_more_than_180_days: 0,
}
stats_days = []

def parse_date(date)
  return :pending if date =~ /pending/i
  return :life if date =~ /life/i
  return :life if date =~ /no parole/i
  return :life if date =~ /death/i

  # some dates have + at the end(?)
  Date.strptime(date.gsub(/\+$/, ''), '%m/%d/%Y')
rescue => ex
  raise "Could not parse date: #{date}"
end

before_file = ARGV.shift
after_file = ARGV.shift

File.open(before_file, 'r') do |f|
  f.each_line do |line|
    l = JSON.parse(line)
    before_by_sid[l['sid']] = l['earliest_release_date']
  end
end

File.open(after_file, 'r') do |f|
  f.each_line do |line|
    l = JSON.parse(line)
    previous_date = parse_date(before_by_sid[l['sid']])
    now_date = parse_date(l['earliest_release_date'])

    if previous_date != now_date
      stats[:total_changed] += 1

      if now_date.is_a?(Date) && previous_date.is_a?(Date)
        difference = now_date - previous_date
        stats_days << difference.to_i
        if difference > 0
          stats[:date_moved_later] += 1
        elsif difference > -14
          stats[:total_moved_earlier] += 1
          stats[:date_moved_earlier_less_than_14_days] += 1
        elsif difference > -90
          stats[:total_moved_earlier] += 1
          stats[:date_moved_earlier_less_than_90_days] += 1
        elsif difference > -180
          stats[:total_moved_earlier] += 1
          stats[:date_moved_earlier_less_than_180_days] += 1
        else
          stats[:total_moved_earlier] += 1
          stats[:date_moved_earlier_more_than_180_days] += 1
        end

        puts "%-56s: %-20s -> %s" % [
          "SID %s, earliest release date changed by %d days" % [
            l['sid'], difference,
          ],
          previous_date,
          now_date
        ]
      elsif now_date.is_a?(Symbol)
        puts "%-56s: %-20s -> %s" % [
          "SID %s, earliest release date changed to pending" % [l['sid']],
          previous_date,
          now_date
        ]
      elsif previous_date.is_a?(Symbol)
        puts "%-56s: %-20s -> %s" % [
          "SID %s, earliest release date was calculated" % [l['sid']],
          previous_date,
          now_date
        ]
      end
    end
  end
end

puts stats.inspect
puts " median days: %d" % [stats_days.sort[stats_days.length / 2]]
puts "average days: %d" % [stats_days.sum / stats_days.length]
