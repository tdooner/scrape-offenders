# usage: pipe this script a bunch of SIDs to check their status
# the first argument can be prior output of this script, in which case the
#   stuff in that file will be skipped

$LOAD_PATH.unshift File.expand_path('~/dev/cfa/oos-mechanizer/lib')
require 'oos_mechanizer'
require 'json'

def throttle(failed = false)
  if failed
    sleep 5
  end
  sleep 0.1
end

$stdout.sync = true

begin
  searcher = OosMechanizer::Searcher.new
  $stdin.each_line do |sid|
    throttle
    $stdout.puts(JSON.generate(searcher.offender_details(sid.strip)))
  end
rescue OosMechanizer::Searcher::ConnectionFailed => ex
  $stderr.puts "Error connecting to OOS: #{ex.message}"
  throttle(true)
  retry
rescue Mechanize::ResponseCodeError => ex
  $stderr.puts "Got Mechanize Error: #{ex.message}"
  throttle(true)
  retry
end
