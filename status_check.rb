# usage: pipe this script a bunch of SIDs to check their status
# the first argument can be prior output of this script, in which case the
#   stuff in that file will be skipped

require 'mechanize'
require 'json'

def throttle(failed = false)
  if failed
    sleep 5
  end
  sleep 0.1
end

$stdout.sync = false

scraper = Mechanize.new

begin
  scraper.get('http://docpub.state.or.us/OOS/intro.jsf') do |page|
    search_page = scraper.click 'I Agree'

    # ['10042337'].each do |sid|
    $stdin.each_line do |sid|
      results_page = search_page.form_with(id: 'mainBodyForm') do |f|
        f['mainBodyForm:SidNumber'] = sid.strip
      end.click_button

      offenses = results_page.css('[id="offensesForm:offensesTable"] tbody tr:nth-child(2n+1)')

      $stdout.puts(JSON.generate(
        sid: results_page.css('[id="offensesForm:out_SID"]').text,
        age: results_page.css('[id="offensesForm:age"]').text,
        gender: results_page.css('[id="offensesForm:sex"]').text,
        # todo all the other fields
        caseload_number: results_page.css('[id="offensesForm:caseloadNumber"]').text,
        caseload_name: results_page.css('[id="offensesForm:caseloadMgrsTable"]').text.strip,
        status: results_page.css('[id="offensesForm:status"]').text,
        location: results_page.css('[id="offensesForm:locationBlock"] a').text,
        admission_date: results_page.css('[id="offensesForm:admitDate"]').text,
        earliest_release_date: results_page.css('[id="offensesForm:relDate"]').text,
        offenses: offenses.map {|o| o.text.strip.gsub(/\s+/, ',') },
        num_offenses: offenses.length,
      ))

      throttle
    end
  end
rescue Mechanize::ResponseCodeError => ex
  $stderr.puts "Got Mechanize Error: #{ex.message}"
  throttle(true)
  retry
end
