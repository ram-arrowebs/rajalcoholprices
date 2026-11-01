"""Fixed-target proxy for the Rajasthan IEMS approved-rate list.

Deployed as an AWS Lambda in ap-south-1 (Mumbai) by scripts/proxy/deploy.sh,
because the IEMS host only accepts connections from Indian IP addresses and
GitHub-hosted runners are not in India.

It fetches exactly one URL, so it cannot be abused as a general-purpose
proxy. Access control is the Function URL's AWS_IAM auth: callers must
SigV4-sign the request with credentials allowed to invoke this function.
"""
import urllib.error
import urllib.request

SOURCE = ("https://iems.rajasthan.gov.in/ApprovedRateList/"
          "ApprovedRateList/ApprovedRateGridList?type=0")


def handler(event, context):
    req = urllib.request.Request(SOURCE, headers={
        "Accept": "application/json",
        "User-Agent": "rajalcoholprices-fetch (+https://github.com/ram-arrowebs/rajalcoholprices)",
    })
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            body = resp.read()
    except urllib.error.HTTPError as exc:
        return {"statusCode": 502, "body": f"upstream returned {exc.code}"}
    except Exception as exc:  # timeout, DNS, TLS
        return {"statusCode": 504, "body": f"upstream error: {exc}"}

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json; charset=utf-8",
                    "Cache-Control": "no-store"},
        "body": body.decode("utf-8"),
    }
