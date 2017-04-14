#!/bin/bash

usage() {
  echo "usage: $0 [statuses-first.json] [statuses-second.json]"
  echo ""
  echo "  e.g: $0 scraped/statuses-2017-03-30.json scraped/statuses-2017-04-07.json"
}

if [ $# -ne 2 ]; then
  usage && exit 1
fi

set -x

first=${1}
second=${2}

mkdir -p tmp
ruby filter_rows.rb $first $second \
  | sort >tmp/after.json
ruby filter_rows.rb tmp/after.json $first \
  | sort >tmp/before.json
ruby look_for_release_date_changes.rb tmp/before.json tmp/after.json
