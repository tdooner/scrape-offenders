scraped/statuses.json: build/offenders.json status_check.rb
	cat build/offenders.json | jq -r .sid \
		| uniq \
		| ruby status_check.rb \
		| pv -i 2 -l -s "$$(cat build/offenders.json | jq -r .sid | sort | uniq | wc -l)" \
		>>$@

build/offenders.json: scraped/out-combined.json
	cat $< | jq -c '.[]' | sort | uniq >$@
