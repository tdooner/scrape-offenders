require 'mechanize'
require 'json'

FIRST_NGRAMS = %W[MA JO JA DA CH RO MI JE BR AN KA CA AL DE KE PA SA SH ST LA LI
  JU DO WI EL RI RA CO NA BE TH ME GA LE AM TA ER NI HA TI LO VI TR RE GE KI TE
  SU EM FR HE GR ED BA AD DI AR AS TO LU PE KR CL RY IS MO AU SE WA NO TY ZA RU
  KY SC CR EV PH VA JI SO BO CY GL LY AB AA GI HO WE OL BI AI VE AV NE ET CE SI
  SY CI DU HU DY FA FE PR BL ES RH IR MY CU GU AP KO EU EA YA QU IA ZO IV YV SK
  AY OS YO FL XA DW DR WY OW MC GW EI KH SP HI OM OR GO WH KU IN EN FI EZ PI YE
  LL BU ZE NY BY IZ IL PO AT EB MU FO IM ZI TU AZ AH AK YU OT ID AG UR OD OC AX
  EF XI UN UL IT ZY WO ZU AJ VO KL SL TW AC IG ON IK AE YI OP IY IB JH IE XZ KN
  OB IO KW OA AF OZ EP NU XO DH DM EY OF HY VL SR TZ WR UM ZH AQ YS EC XE DJ FU
  EG SM JY EW PU UZ BJ OU SV QI SW NG AW EH AO US EO SN KC EX NN NH PY TJ OV VY
  GY UB IC BH EK QA OK JL JR PL XY JD JC DV EE KJ JS IF TK GH JN CJ VU DS ND OO
  FY IQ YL JV IX JM DN KS UC NK HR MK WM IJ JJ UG KM RJ OG IH OH VR TS LT ZV KV
  UV JQ YZ JW EQ CZ OJ JK XU ZS UD JB TN JT UT UY SZ ZL OY EJ NZ RM YM ZN II KD
  NJ DL OI LC MD ML MR DQ YG QW PS TL TV YT DZ PJ CN LJ TM SQ IW HL XS YN XX DK
  XH UI ZM UK WL MH JG XC YH MJ TC ZR WU JP NT UH RC GJ FH UW SJ HS BG IP WW OX
  MB DD RW DC UP BB NS ZB PT JZ HT KT YK PN MM CM RP NC PF OE LW VH LH GN RR MT
  LB ZK YR UJ SS SB RB QM PP LD IU UF QO YD TQ TP HJ BN ZZ ZX YW XJ WN VS UA RD
  QY NW MG LR KF GZ FJ CS CC BW BT]

class NoPaginationError < StandardError; end

class PrefixIgnorer
  def initialize
    @state = Hash[JSON.parse(File.read('prefixes.json')).map { |k, v| [JSON.parse(k), v] }]
  rescue
    $logger.warn 'Prefixes file not found'
    @state = {}
  end

  def should_skip_prefix?(first, last)
    return true if first.length > 1 && !FIRST_NGRAMS.include?(first[0..1])

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

def search_for_prefix(search_page, first, last)
  $logger.debug "Searching for #{first}* #{last}*"
  results_page = search_page.form_with(id: 'mainBodyForm') do |f|
    f['mainBodyForm:FirstName'] = "#{first}*"
    f['mainBodyForm:LastName'] = "#{last}*"
  end.click_button

  throttle

  if results_page.css('.infoMessage').text =~ /Too many/
    $logger.debug "  too many results"
    # if there are too many results, get more specific with the first name
    ('A'..'Z').to_a.repeated_permutation(2).flat_map do |c1, c2|
      # skip the prefix if we've seen it already
      next [] if $prefixes.should_skip_prefix?(first + c1, last + c2)

      search_for_prefix(search_page, first + c1, last + c2).tap do |results|
        # save prefix state
        $prefixes.save_prefix_state(first + c1, last + c2, results.length)

        $logger.debug "  Got #{results.length} results"
      end
    end
  elsif results_page.css('.infoMessage').text =~ /No matching/
    []
  elsif results_page.css('#offensesForm')
    # if there is one result, click back to the table view
    back_button = results_page.forms.first.button_with(value: 'Back')
    results_page = results_page.forms.first.submit(back_button)
    process_results(results_page)
  else
    $logger.debug "  many results"
    # if there are results, paginate through them
    process_results(results_page)
  end
end

def throttle
  sleep 0.1
end

begin
  $prefixes = PrefixIgnorer.new
  scraper = Mechanize.new
  scraper.get('http://docpub.state.or.us/OOS/intro.jsf') do |page|
    search_page = scraper.click 'I Agree'

    ('A'..'Z').each do |first_prefix|
      ('A'..'Z').each do |last_prefix|
        # skip the prefix if we've seen it already
        next [] if $prefixes.should_skip_prefix?(first_prefix, last_prefix)

        results = search_for_prefix(search_page, first_prefix, last_prefix)

        $prefixes.save_prefix_state(first_prefix, last_prefix, results.length)

        $stdout.puts JSON.generate(results)
        $logger.info "Got #{results.length} results"
      end
    end
  end
rescue NoPaginationError
  $stderr.puts "GOT NO PAGINATION ERROR, retrying"
  $prefixes.close
  retry
ensure
  $prefixes.close
end
