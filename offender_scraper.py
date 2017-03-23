from string import ascii_uppercase
import scrapy
import re

# A* A*, A* B*, ..., Z* Z*
# if A* A* returns too many matches:
#   recurse, with AA* AA* through AZ* AZ*
# if returns no matches, done

class OffenderScraper(scrapy.Spider):
    name = "offenders"
    custom_settings = {
        'AUTOTHROTTLE_ENABLED': 1,
        'CONCURRENT_REQUESTS': 1,
    }

    def start_requests(self):
        return [scrapy.Request('http://docpub.state.or.us/OOS/intro.jsf', callback=self.hit_agree)]

    def hit_agree(self, response):
        return [scrapy.FormRequest.from_response(response, formname='disclaimerForm', callback=self.perform_search)]

    def perform_search(self, response):
        """
        This is the recursive method.
        """
        return self._next_requests(response)

    def _next_requests(self, response):
        prefix_first = response.meta.get('prefix_first', '')
        prefix_last = response.meta.get('prefix_last', '')

        for first in ascii_uppercase:
            for last in ascii_uppercase:
                yield scrapy.FormRequest.from_response(response, formname='mainBodyForm', formdata={
                    'mainBodyForm:FirstName': prefix_first + first + '*',
                    'mainBodyForm:LastName': prefix_last + last + '*',
                    }, meta={'prefix_first': prefix_first + first, 'prefix_last': prefix_last + last},
                    callback=self.parse_search_results)

    def parse_search_results(self, response):
        error = response.xpath('//*[@id = "errorMessages"]/table/tr/td/text()').extract_first()
        if error and re.search('Too many', error) is not None:
            # We need to recurse!
            print "GOT ERROR TOO MANY FOR {}* {}*".format(response.meta['prefix_first'], response.meta['prefix_last'])
            for request in self._next_requests(response):
                yield request
        elif error and re.search('No matching records', error) is not None:
            print "No results for {}* {}*".format(response.meta['prefix_first'], response.meta['prefix_last'])
            yield None
        else:
            if response.css('#offensesForm'):
                # there is only a single offender
                yield {
                    'sid': response.css('[id="offensesForm:out_SID"] ::text').extract_first(),
                    'name': response.css('[id="offensesForm:name"] ::text').extract_first(),
                }
            elif response.css('.foundOffenders'):
                # TODO: paginate this
                for row in response.css('.foundOffenders tbody tr'):
                    yield {
                        'sid': row.css('td:nth-child(1) ::text').extract_first(),
                        'first': row.css('td:nth-child(2) ::text').extract_first(),
                        'middle': row.css('td:nth-child(3) ::text').extract_first(),
                        'last': row.css('td:nth-child(4) ::text').extract_first(),
                    }
            else:
                print "unknown page detected:"
                import ipdb
                ipdb.set_trace()
