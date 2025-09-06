ES_HOST="https://ip:9200"
CA_CERT="/ElasticSearch/certs/ca/ca.crt"
AUTH="elastic:Sp@n#TBSDEvES2025"
INDEX="${ES_INDEX:-indexnames}"
S3_BUCKET="bucketname"  # Replace with your actual bucket name
S3_REGION="ap-south-1"
BATCH_SIZE=10000
SCROLL_TIME="60m"

# Generate timestamp for filename
S3_FILENAME="${INDEX}.json"
S3_PATH="s3://${S3_BUCKET}/${INDEX}/${S3_FILENAME}"
TEMP_FILE="/tmp/temp_batch.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== ELASTICSEARCH SCROLL EXPORT TO S3 ===${NC}"
echo "Source Index: $INDEX"
echo "S3 Location: $S3_PATH"

# Function to check AWS CLI
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI is not installed. Please install it first.${NC}"
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}AWS credentials not configured or invalid.${NC}"
        exit 1
    fi

    echo -e "${GREEN} AWS CLI configured${NC}"
}

# Function to check S3 bucket
check_s3_bucket() {
    if ! aws s3 ls "s3://${S3_BUCKET}" &> /dev/null; then
        echo -e "${RED}S3 bucket '${S3_BUCKET}' not found or not accessible.${NC}"
        exit 1
    fi
    echo -e "${GREEN} S3 bucket accessible${NC}"
}

# Function to upload batch to S3
upload_batch_to_s3() {
    local batch_data="$1"
    local is_first_batch="$2"

    # Write batch to temp file
    echo "$batch_data" > "$TEMP_FILE"

    if [ "$is_first_batch" = "true" ]; then
        # First batch - create new file
        aws s3 cp "$TEMP_FILE" "$S3_PATH" --region "$S3_REGION" >/dev/null
    else
        # Subsequent batches - append to existing file
        # Download existing file, append new data, upload back
        aws s3 cp "$S3_PATH" "/tmp/existing.json" --region "$S3_REGION" >/dev/null
        cat "/tmp/existing.json" "$TEMP_FILE" > "/tmp/combined.json"
        aws s3 cp "/tmp/combined.json" "$S3_PATH" --region "$S3_REGION" >/dev/null
        rm -f "/tmp/existing.json" "/tmp/combined.json"
    fi

    rm -f "$TEMP_FILE"
}

# Main export function
export_to_s3() {
    echo -e "${YELLOW}Starting Elasticsearch scroll export to S3...${NC}"

    # 1. Initial scroll request
    echo "Making initial scroll request..."
    echo "Debug: BATCH_SIZE=$BATCH_SIZE, SCROLL_TIME=$SCROLL_TIME"
    response=$(curl -s -X POST "$ES_HOST/$INDEX/_search?scroll=$SCROLL_TIME&size=$BATCH_SIZE" \
      --cacert "$CA_CERT" \
      -u "$AUTH" \
      -H 'Content-Type: application/json' \
      -d "{
        \"_source\": true,
        \"query\": {
          \"match_all\": {}
        }
      }")

    # Check for errors
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        echo -e "${RED}Error in initial scroll request:${NC}"
        echo "$response" | jq '.error'
        exit 1
    fi

    scroll_id=$(echo "$response" | jq -r '._scroll_id')
    hits=$(echo "$response" | jq '.hits.hits')

    if [ "$scroll_id" = "null" ]; then
        echo -e "${RED}Failed to get scroll_id from initial request${NC}"
        exit 1
    fi

    # Upload first batch to S3
    batch_data=$(echo "$hits" | jq -c '.[]')
    upload_batch_to_s3 "$batch_data" "true"

    initial_count=$(echo "$hits" | jq length)
    echo "Initial batch: $initial_count documents uploaded to S3"
    total_count=$initial_count
    batch_num=1

    # 2. Loop over scrolls
    echo "Continuing with scroll requests..."
    while true; do
        response=$(curl -s -X POST "$ES_HOST/_search/scroll" \
          --cacert "$CA_CERT" \
          -u "$AUTH" \
          -H 'Content-Type: application/json' \
          -d "{
            \"scroll\": \"$SCROLL_TIME\",
            \"scroll_id\": \"$scroll_id\"
          }")

        # Check for errors
        if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
            echo -e "${YELLOW}Warning: Error in scroll request${NC}"
            break
        fi

        scroll_id=$(echo "$response" | jq -r '._scroll_id')
        hits=$(echo "$response" | jq '.hits.hits')

        if [[ "$hits" == "[]" ]] || [[ "$hits" == "null" ]]; then
            echo "No more documents to fetch"
            break
        fi

        # Upload batch to S3
        batch_data=$(echo "$hits" | jq -c '.[]')
        upload_batch_to_s3 "$batch_data" "false"

        batch_count=$(echo "$hits" | jq length)
        total_count=$((total_count + batch_count))
        batch_num=$((batch_num + 1))

        echo "Batch $batch_num: $batch_count documents uploaded (Total: $total_count)"

        # Small delay to avoid overwhelming ES and S3
        sleep 0.2
    done

    # Clear the scroll
    if [ "$scroll_id" != "null" ]; then
        curl -s -X DELETE "$ES_HOST/_search/scroll" \
          --cacert "$CA_CERT" \
          -u "$AUTH" \
          -H 'Content-Type: application/json' \
          -d "{\"scroll_id\": \"$scroll_id\"}" >/dev/null
    fi

    echo -e "${GREEN}✅ Export completed: $total_count documents saved to S3${NC}"
    return $total_count
}

# Main execution
main() {
    check_aws_cli
    check_s3_bucket

    export_to_s3
    exported_count=$?

    # Verify final S3 file
    if aws s3 ls "$S3_PATH" --region "$S3_REGION" >/dev/null; then
        S3_FILE_SIZE=$(aws s3 ls "$S3_PATH" --region "$S3_REGION" | awk '{print $3}')
        echo -e "${GREEN}S3 file size: ${S3_FILE_SIZE} bytes${NC}"

        # Count lines in S3 file to verify
        aws s3 cp "$S3_PATH" "/tmp/verify.json" --region "$S3_REGION" >/dev/null
        actual_lines=$(wc -l < "/tmp/verify.json")
        rm -f "/tmp/verify.json"

        echo -e "${GREEN}Verified: $actual_lines documents in S3 file${NC}"
    fi

    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}EXPORT COMPLETED${NC}"
    echo -e "${GREEN}Source Index: $INDEX${NC}"
    echo -e "${GREEN}Documents Exported: $exported_count${NC}"
    echo -e "${GREEN}S3 Location: ${S3_PATH}${NC}"
    echo -e "${GREEN}Filename: ${S3_FILENAME}${NC}"
    echo -e "${GREEN}================================${NC}"

    echo -e "${GREEN}S3 Commands:${NC}"
    echo "List files: aws s3 ls s3://${S3_BUCKET}/${INDEX}/"
    echo "Download: aws s3 cp ${S3_PATH} ./"
    echo "View first 10 lines: aws s3 cp ${S3_PATH} - | head -10"
}

# Run main function
main

