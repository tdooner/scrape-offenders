require 'mechanize'
require 'json'

class NoPaginationError < StandardError; end

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

def process_results(results_page)
  results = []

  pagination = results_page.xpath('//*[@id="mainBodyForm:pageMsg"]').text().match(/Page (\d)\/(\d)/)
  results += process_results_from_table(results_page)

  if !pagination
    $stderr.puts 'ERROR NO PAGINATION CONTROLS'
    raise NoPaginationError
  end

  (pagination[2].to_i - pagination[1].to_i).times do
    results_page = results_page.forms.first.tap do |f|
      f['mainBodyForm:j_id30.x'] = '1'
      f['mainBodyForm:j_id30.y'] = '1'
    end.submit

    results += process_results_from_table(results_page)
  end

  results
end

def process_results_from_table(page)
  page.css('.foundOffenders tbody tr').map do |row|
    {
      sid: row.css('td:nth-child(1)').text,
      first: row.css('td:nth-child(2)').text,
      middle: row.css('td:nth-child(3)').text,
      last: row.css('td:nth-child(4)').text,
      dob: row.css('td:nth-child(5)').text,
    }
  end
end

class Scraper
  def initialize(throttle = 0.1)
    @prefixes = PrefixIgnorer.new
    @scraper = Mechanize.new
    @throttle = throttle
    @outfile = File.open('out.json', 'a').tap { |f| f.sync = true }
  end

  def scrape
    @scraper.get('http://docpub.state.or.us/OOS/intro.jsf') do |page|
      search_page = @scraper.click 'I Agree'

      ('A'..'Z').each do |first_prefix|
        ('A'..'Z').each do |last_prefix|
          # skip the prefix if we've seen it already
          next if @prefixes.should_skip_prefix?(first_prefix, last_prefix)

          search_for_prefix(search_page, first_prefix, last_prefix)

          @prefixes.save_prefix_state(first_prefix, last_prefix, 'some')
        end
      end
    end
  end

  def close
    @prefixes.close
    @outfile.close
  end

  private

  def search_for_prefix(search_page, first, last)
    $logger.debug "Searching for #{first}* #{last}*"
    results_page = search_page.form_with(id: 'mainBodyForm') do |f|
      f['mainBodyForm:FirstName'] = "#{first}*"
      f['mainBodyForm:LastName'] = "#{last}*"
    end.click_button

    sleep $throttle

    if results_page.css('.infoMessage').text =~ /Too many/
      $logger.debug "  too many results"
      # if there are too many results, get more specific with the first name
      ('A'..'Z').to_a.flat_map do |c1|
        # skip the prefix if we've seen it already
        next [] if @prefixes.should_skip_prefix?(first, last + c1)

        search_for_prefix(search_page, first, last + c1)

        @prefixes.save_prefix_state(first, last + c1, 'some')
      end
    elsif results_page.css('.infoMessage').text =~ /No matching/
      # no results; do nothing
    elsif results_page.css('#offensesForm')
      # if there is one result, click back to the table view
      back_button = results_page.forms.first.button_with(value: 'Back')
      results_page = results_page.forms.first.submit(back_button)
      process_results(results_page).each do |result|
        output_result(result)
      end
    else
      $logger.debug "  many results"
      # if there are results, paginate through them
      process_results(results_page).each do |result|
        output_result(result)
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
rescue Mechanize::ResponseCodeError
  $stderr.puts "GOT BAD RESPONSE CODE ERROR, slowing down"
  $throttle += 0.1
  sleep 60
  scraper.close
  retry
rescue NoPaginationError
  $stderr.puts "GOT NO PAGINATION ERROR, retrying"
  scraper.close
  retry
ensure
  scraper.close
end
