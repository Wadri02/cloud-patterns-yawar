"""
Minimal local emulator of the Lambda runtime: loads the handler once (like an execution
environment), builds a context object with a timeout and invokes it with sample events.
Usage: python local_invoke.py events/*.json
"""
import importlib, json, sys, time, uuid


class Context:
    def __init__(self, timeout_s=3, memory=128):
        self.aws_request_id = str(uuid.uuid4())
        self.function_name = "yawar-blood-stock-alert"
        self.memory_limit_in_mb = memory
        self._deadline = time.time() + timeout_s

    def get_remaining_time_in_millis(self):
        return int((self._deadline - time.time()) * 1000)


t0 = time.perf_counter()
handler = importlib.import_module("handler")          # INIT phase (cold start)
init_ms = (time.perf_counter() - t0) * 1000
print(f"INIT_START Runtime: python{sys.version_info.major}.{sys.version_info.minor}  init={init_ms:.2f} ms")
for path in sys.argv[1:]:
    event = json.load(open(path))
    ctx = Context()
    print(f"START RequestId: {ctx.aws_request_id}  event={path}")
    t = time.perf_counter()
    out = handler.lambda_handler(event, ctx)
    dur = (time.perf_counter() - t) * 1000
    print(f"END   status={out['statusCode']} body={out['body']}")
    print(f"REPORT Duration: {dur:.2f} ms  Billed Duration: {max(1, round(dur))} ms  Memory Size: {ctx.memory_limit_in_mb} MB\n")
