import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
import handler  # noqa: E402

EV = os.path.join(os.path.dirname(os.path.dirname(__file__)), "events")


def load(name):
    with open(os.path.join(EV, name)) as f:
        return json.load(f)


def test_api_gateway_event_returns_critical_types():
    out = handler.lambda_handler(load("api_gateway_post.json"), None)
    body = json.loads(out["body"])
    assert out["statusCode"] == 200
    assert body["critical"] == ["B-", "O-"]
    assert "Need O- donors at Hospital Eugenio Espejo" in body["notify"]


def test_scheduled_event_uses_snapshot():
    body = json.loads(handler.lambda_handler(load("eventbridge_schedule.json"), None)["body"])
    assert body["critical"] == ["AB-", "O-"]


def test_invalid_blood_type_is_400():
    out = handler.lambda_handler(load("bad_request.json"), None)
    assert out["statusCode"] == 400


def test_only_first_invocation_is_cold():
    handler._COLD = True
    a = json.loads(handler.lambda_handler(load("eventbridge_schedule.json"), None)["body"])
    b = json.loads(handler.lambda_handler(load("eventbridge_schedule.json"), None)["body"])
    assert a["coldStart"] is True and b["coldStart"] is False
