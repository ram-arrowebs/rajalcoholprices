#!/usr/bin/env bash
# Deploy (or update) the IEMS proxy Lambda in AWS ap-south-1 (Mumbai) and
# point the GitHub workflow at it. Safe to rerun; it converges on:
#
#   IAM role      rajalcoholprices-iems-proxy  execution role for the Lambda
#   Lambda        rajalcoholprices-iems-proxy  python3.12, 128 MB, 30 s
#   Function URL  auth type AWS_IAM (no public access)
#   IAM user      rajalcoholprices-fetch       may only invoke that URL;
#                 its access key is rotated on every run
#
# and on the GitHub repo, all as secrets so the runner masks them in the
# public Actions log:
#   SOURCE_URL             the Function URL
#   AWS_ACCESS_KEY_ID      the fetch user's key
#   AWS_SECRET_ACCESS_KEY
#
# Needs: aws (authenticated), gh (authenticated), zip, curl, jq.
# Cost: one invocation a day sits inside the Lambda free tier.
# Remove everything with:  scripts/proxy/deploy.sh --destroy
set -euo pipefail

NAME="rajalcoholprices-iems-proxy"
USER_NAME="rajalcoholprices-fetch"
REGION="${AWS_REGION_OVERRIDE:-ap-south-1}"
here="$(cd "$(dirname "$0")" && pwd)"

delete_user_keys() {
  for key in $(aws iam list-access-keys --user-name "$USER_NAME" \
                 --query 'AccessKeyMetadata[].AccessKeyId' --output text 2> /dev/null); do
    aws iam delete-access-key --user-name "$USER_NAME" --access-key-id "$key"
  done
}

if [ "${1:-}" = "--destroy" ]; then
  aws lambda delete-function --region "$REGION" --function-name "$NAME" 2> /dev/null || true
  aws iam detach-role-policy --role-name "$NAME" \
      --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2> /dev/null || true
  aws iam delete-role --role-name "$NAME" 2> /dev/null || true
  delete_user_keys
  aws iam delete-user-policy --user-name "$USER_NAME" --policy-name invoke-proxy 2> /dev/null || true
  aws iam delete-user --user-name "$USER_NAME" 2> /dev/null || true
  gh variable delete SOURCE_URL 2> /dev/null || true
  for s in SOURCE_URL AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY PROXY_TOKEN; do gh secret delete "$s" 2> /dev/null || true; done
  echo "Removed Lambda, role, fetch user, and the repo secrets."
  exit 0
fi

for tool in aws gh zip curl jq; do
  command -v "$tool" > /dev/null || { echo "$tool is required" >&2; exit 1; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
(cd "$here" && zip -q "$tmp/proxy.zip" proxy.py)
fn_arn="arn:aws:lambda:$REGION:$(aws sts get-caller-identity --query Account --output text):function:$NAME"

# --- Execution role ---------------------------------------------------------
if ! role_arn="$(aws iam get-role --role-name "$NAME" --query Role.Arn --output text 2> /dev/null)"; then
  cat > "$tmp/trust.json" <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
 "Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
  role_arn="$(aws iam create-role --role-name "$NAME" \
      --description "Execution role for the IEMS price-list proxy (rajalcoholprices)" \
      --assume-role-policy-document "file://$tmp/trust.json" \
      --query Role.Arn --output text)"
  aws iam attach-role-policy --role-name "$NAME" \
      --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  echo "Created role $role_arn; waiting for it to propagate"
  sleep 12
fi

# --- Lambda -----------------------------------------------------------------
if aws lambda get-function --region "$REGION" --function-name "$NAME" > /dev/null 2>&1; then
  aws lambda update-function-code --region "$REGION" --function-name "$NAME" \
      --zip-file "fileb://$tmp/proxy.zip" > /dev/null
  aws lambda wait function-updated --region "$REGION" --function-name "$NAME"
  # Drop any environment left over from earlier token-based versions.
  aws lambda update-function-configuration --region "$REGION" --function-name "$NAME" \
      --environment '{"Variables":{}}' > /dev/null
  echo "Updated Lambda $NAME"
else
  for attempt in 1 2 3 4 5; do
    if aws lambda create-function --region "$REGION" --function-name "$NAME" \
        --description "Fetches the Rajasthan IEMS approved-rate list from an Indian IP for the rajalcoholprices GitHub Action" \
        --runtime python3.12 --handler proxy.handler --role "$role_arn" \
        --zip-file "fileb://$tmp/proxy.zip" --timeout 30 --memory-size 128 > /dev/null 2> "$tmp/err"; then
      break
    fi
    # A freshly created role can take a few seconds to become assumable.
    if grep -q "cannot be assumed" "$tmp/err" && [ "$attempt" -lt 5 ]; then sleep 8; continue; fi
    cat "$tmp/err" >&2; exit 1
  done
  echo "Created Lambda $NAME in $REGION"
fi
aws lambda wait function-updated --region "$REGION" --function-name "$NAME"

# --- Function URL (IAM auth) ------------------------------------------------
if url="$(aws lambda get-function-url-config --region "$REGION" --function-name "$NAME" \
            --query FunctionUrl --output text 2> /dev/null)"; then
  auth="$(aws lambda get-function-url-config --region "$REGION" --function-name "$NAME" \
            --query AuthType --output text)"
  if [ "$auth" != "AWS_IAM" ]; then
    aws lambda update-function-url-config --region "$REGION" --function-name "$NAME" \
        --auth-type AWS_IAM > /dev/null
    echo "Switched Function URL to AWS_IAM auth"
  fi
else
  url="$(aws lambda create-function-url-config --region "$REGION" --function-name "$NAME" \
           --auth-type AWS_IAM --query FunctionUrl --output text)"
  echo "Created Function URL"
fi
# Remove the public-access grant from earlier versions, if present.
aws lambda remove-permission --region "$REGION" --function-name "$NAME" \
    --statement-id public-url 2> /dev/null && echo "Removed public-url permission" || true

# --- Fetch user: may only invoke this one URL -------------------------------
if ! aws iam get-user --user-name "$USER_NAME" > /dev/null 2>&1; then
  aws iam create-user --user-name "$USER_NAME" > /dev/null
  echo "Created IAM user $USER_NAME"
fi
cat > "$tmp/invoke.json" <<JSON
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
 "Action":["lambda:InvokeFunctionUrl","lambda:InvokeFunction"],
 "Resource":"$fn_arn"}]}
JSON
aws iam put-user-policy --user-name "$USER_NAME" --policy-name invoke-proxy \
    --policy-document "file://$tmp/invoke.json"
delete_user_keys
key_json="$(aws iam create-access-key --user-name "$USER_NAME" --query AccessKey --output json)"
ak="$(jq -r .AccessKeyId <<< "$key_json")"
sk="$(jq -r .SecretAccessKey <<< "$key_json")"
echo "Rotated access key for $USER_NAME"

# --- Smoke test -------------------------------------------------------------
code_unsigned="$(curl -s -o /dev/null -w '%{http_code}' "$url")"
rows=0
for attempt in 1 2 3 4 5 6; do   # new IAM keys take a few seconds to propagate
  rows="$(curl -sf --aws-sigv4 "aws:amz:$REGION:lambda" --user "$ak:$sk" "$url" \
            | jq '.data | length' 2> /dev/null || echo 0)"
  [ "$rows" -gt 0 ] && break
  sleep 5
done
echo "Smoke test: unsigned HTTP $code_unsigned (expect 403); signed returned $rows rows"
if [ "$code_unsigned" != "403" ] || [ "$rows" -le 0 ]; then
  echo "Smoke test failed; not touching the GitHub settings." >&2
  exit 1
fi

# --- GitHub -----------------------------------------------------------------
gh secret set SOURCE_URL --body "$url"
gh secret set AWS_ACCESS_KEY_ID --body "$ak"
gh secret set AWS_SECRET_ACCESS_KEY --body "$sk"
# Leftovers from earlier versions that stored these differently.
gh variable delete SOURCE_URL 2> /dev/null || true
gh secret delete PROXY_TOKEN 2> /dev/null || true
echo "Set repo secrets SOURCE_URL ($url) and AWS_*."
echo "Trigger a run with: gh workflow run fetch-prices.yml --ref main"
