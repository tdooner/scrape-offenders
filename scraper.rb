$LOAD_PATH.unshift File.expand_path('~/dev/cfa/oos-mechanizer/lib')
require 'oos_mechanizer'
require 'json'

class PrefixIgnorer
  def initialize
    @state = Hash[JSON.parse(File.read('prefixes.json')).map { |k, v| [JSON.parse(k), v] }]
  rescue
    $logger.warn 'Prefixes file not found'
    @state = {}
  end

  def should_skip_prefix?(first, last)
    @state.include?([first, last])
  end

  def save_prefix_state(first, last, num_results)
    @state[[first, last]] = num_results
  end

  def close
    File.open('prefixes.json', 'w') do |f|
      f.puts JSON.generate(@state)
    end
  end
end

$logger = Logger.new($stderr)

class Scraper
  def initialize(throttle = 0.1)
    @prefixes = PrefixIgnorer.new
    @searcher = OosMechanizer::Searcher.new
    @throttle = throttle
    @outfile = File.open('out.json', 'a').tap { |f| f.sync = true }
  end

  def scrape
    ('A'..'Z').each do |first_prefix|
      ('A'..'Z').each do |last_prefix|
        # skip the prefix if we've seen it already
        next if @prefixes.should_skip_prefix?(first_prefix, last_prefix)

        search_for_prefix(first_prefix, last_prefix)

        sleep $throttle

        @prefixes.save_prefix_state(first_prefix, last_prefix, 'some')
      end
    end
  end

  def close
    @prefixes.close
    @outfile.close
  end

  private

  def search_for_prefix(first, last)
    $logger.debug "Searching for #{first}* #{last}*"

    begin
      @searcher.each_result(first_name: first, last_name: last) do |result|
        output_result(result)
      end

      sleep $throttle

      @prefixes.save_prefix_state(first, last, 'some')
    rescue OosMechanizer::Searcher::TooManyResultsError
      ('A'..'Z').to_a.flat_map do |c1|
        search_for_prefix(first, last + c1)
      end
    end
  end

  def output_result(result)
    @outfile.puts(JSON.generate(result))
  end
end

$throttle = 0.1
begin
  scraper = Scraper.new($throttle)
  scraper.scrape
rescue OosMechanizer::Searcher::ResponseCodeError
  $stderr.puts "GOT BAD RESPONSE CODE ERROR, slowing down"
  $throttle += 0.1
  sleep 60
  scraper.close
  retry
rescue OosMechanizer::Searcher::NoPaginationError
  $stderr.puts "GOT NO PAGINATION ERROR, retrying"
  scraper.close
  retry
ensure
  scraper.close
end
