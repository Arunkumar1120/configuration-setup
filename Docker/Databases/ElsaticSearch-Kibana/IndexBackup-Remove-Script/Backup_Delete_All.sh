#!/bin/bash

ES_HOST="https://ip:9200"
AUTH="elastic:password"
CA_CERT="/ElasticSearch/certs/ca/ca.crt"

INDEXES=(
Index Names
)

# ==== Export All Indexes ====
export_success=true

for index in "${INDEXES[@]}"; do
  echo -e "\n==============================="
  echo -e "Exporting index: $index"
  echo -e "==============================="

  ES_INDEX="$index" \
  ES_HOST="$ES_HOST" \
  AUTH="$AUTH" \
  CA_CERT="$CA_CERT" \
  /ElasticSearch/script/export_to_s3.sh

  if [ $? -ne 0 ]; then
    echo -e "\033[0;31m Export failed for index: $index. Aborting deletion.\033[0m"
    export_success=false
    break
  fi
done

# ==== Delete All Indexes ====
if [ "$export_success" = true ]; then
  echo -e "\n All exports successful. Proceeding to delete indexes..."

  for index in "${INDEXES[@]}"; do
    echo -e " Deleting index: $index"
    curl -s -X DELETE "$ES_HOST/$index" \
      --cacert "$CA_CERT" \
      -u "$AUTH" \
      -H 'Content-Type: application/json'

    echo "✔ Deleted: $index"
  done
else
  echo -e "\n Skipping deletion since export failed for one or more indexes."
fi

