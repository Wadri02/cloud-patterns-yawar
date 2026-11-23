"""
Yawar - blood-stock-alert (AWS Lambda, Python 3.14)

Triggered by:
  * Amazon API Gateway (HTTP API, payload v2)  POST /stock-alerts  {"center": "...", "stock": {"O+": 42, ...}}
  * Amazon EventBridge schedule (every hour) -> checks a default snapshot

Returns which blood types are under the critical threshold so ms-notifications
(Telegram) can call donors with that blood type.
"""
import json
import os
import time

# Code outside the handler runs once per execution environment (= cold start).
_COLD = True
_INIT_AT = time.time()
MIN_UNITS = int(os.environ.get("MIN_UNITS", "5"))
VALID_TYPES = {"O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"}


def evaluate(center: str, stock: dict) -> dict:
    unknown = sorted(set(stock) - VALID_TYPES)
    if unknown:
        raise ValueError(f"unknown blood types: {unknown}")
    critical = sorted(t for t, units in stock.items() if int(units) < MIN_UNITS)
    return {
        "center": center,
        "threshold": MIN_UNITS,
        "critical": critical,
        "notify": [f"Need {t} donors at {center}" for t in critical],
    }


def _response(status: int, body: dict) -> dict:
    return {"statusCode": status, "headers": {"Content-Type": "application/json"}, "body": json.dumps(body, ensure_ascii=False)}


def lambda_handler(event, context):
    global _COLD
    cold, _COLD = _COLD, False
    meta = {"coldStart": cold, "requestId": getattr(context, "aws_request_id", "local"),
            "remainingMs": context.get_remaining_time_in_millis() if context else None}
    try:
        if event.get("source") == "aws.events":           # EventBridge scheduled run
            result = evaluate("HCAM Quito", {"O+": 42, "O-": 3, "A+": 18, "AB-": 1})
        else:                                             # API Gateway HTTP API v2
            body = json.loads(event.get("body") or "{}")
            result = evaluate(body["center"], body["stock"])
        print(json.dumps({"level": "INFO", "msg": "evaluated", **meta, "critical": result["critical"]}))
        return _response(200, {**result, **meta})
    except (KeyError, ValueError, json.JSONDecodeError) as e:
        print(json.dumps({"level": "WARN", "msg": "bad request", "error": str(e), **meta}))
        return _response(400, {"error": str(e), **meta})
