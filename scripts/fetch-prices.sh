#!/usr/bin/env bash
# Download the IEMS approved-rate list, validate it, and write
# data/prices.json and data/meta.json.
#
# Used by .github/workflows/fetch-prices.yml and runnable by hand. The
# target files are only written after the payload passes validation, so a
# network error, non-200 response, malformed JSON or an empty/misshapen
# list exits non-zero and leaves any existing data untouched.
#
# Environment:
#   SOURCE_URL             endpoint to download (default: the IEMS URL below,
#                          or the Lambda Function URL from scripts/proxy/deploy.sh)
#   AWS_ACCESS_KEY_ID      if both are set, the request is SigV4-signed, which
#   AWS_SECRET_ACCESS_KEY  the proxy's IAM-authenticated Function URL requires
#   DATA_DIR               directory to write into (default: data)
set -euo pipefail

SOURCE_URL="${SOURCE_URL:-https://iems.rajasthan.gov.in/ApprovedRateList/ApprovedRateList/ApprovedRateGridList?type=0}"
DATA_DIR="${DATA_DIR:-data}"
TARGET="$DATA_DIR/prices.json"
META="$DATA_DIR/meta.json"

for tool in curl jq; do
  if ! command -v "$tool" > /dev/null; then
    echo "::error::$tool is required but not installed" >&2
    exit 1
  fi
done

raw="$(mktemp)"
trap 'rm -f "$raw"' EXIT

auth=()
if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  # Region comes from the Function URL (xxx.lambda-url.<region>.on.aws).
  region="$(sed -E 's#^https?://[^/]*\.lambda-url\.([a-z0-9-]+)\.on\.aws.*#\1#' <<< "$SOURCE_URL")"
  [ "$region" = "$SOURCE_URL" ] && region="${AWS_REGION:-ap-south-1}"
  auth=(--aws-sigv4 "aws:amz:$region:lambda" --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY")
fi

# The IEMS host drops connections from outside India (the SYN is never
# answered, so curl reports a connect timeout rather than an HTTP error).
# Keep the connect timeout short so a blocked machine fails in about a
# minute instead of tying up a runner for ten.
if ! curl --fail --silent --show-error --location \
          --connect-timeout 15 --max-time 90 \
          --retry 2 --retry-delay 10 --retry-all-errors \
          -H "Accept: application/json" ${auth[@]+"${auth[@]}"} \
          -o "$raw" "$SOURCE_URL"; then
  # Deliberately not echoing the URL: on a public repo the Actions log is
  # public too, and the proxy's Function URL need not be.
  cat >&2 <<MSG
::error::Could not download the price list from SOURCE_URL
The IEMS host only accepts connections from Indian IP addresses, and
GitHub-hosted runners are outside India. Either run this from a machine in
India (scripts/publish-prices.sh, or a self-hosted runner selected with the
FETCH_RUNNER repository variable) or deploy the India-hosted proxy with
scripts/proxy/deploy.sh, which sets the SOURCE_URL variable and the AWS_*
secrets for you.
MSG
  exit 1
fi

if ! jq -e '.data | type == "array" and length > 0' "$raw" > /dev/null; then
  echo "::error::Source returned no rows or invalid JSON; keeping previous data" >&2
  head -c 500 "$raw" >&2 || true
  exit 1
fi

# index.html reads exactly these keys; a renamed field upstream would
# otherwise be committed and render as "undefined".
if ! jq -e '.data | all(has("BrandName") and has("Packing") and has("MRP") and has("Type"))' "$raw" > /dev/null; then
  echo "::error::Source rows are missing expected fields; keeping previous data" >&2
  jq -c '.data[0]' "$raw" >&2 || true
  exit 1
fi

rows="$(jq '.data | length' "$raw")"
mkdir -p "$DATA_DIR"
jq '.' "$raw" > "$TARGET"
jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson rows "$rows" \
      '{fetchedAt: $at, rows: $rows}' > "$META"

echo "Wrote $TARGET ($rows rows) and $META"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "rows=$rows" >> "$GITHUB_STEP_SUMMARY"
fi
