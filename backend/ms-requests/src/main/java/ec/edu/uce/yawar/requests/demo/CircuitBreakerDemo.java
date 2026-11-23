package ec.edu.uce.yawar.requests.demo;

import ec.edu.uce.yawar.requests.client.InventoryClient;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Supplier;

/**
 * 30 calls from ms-requests to ms-inventory: healthy (1-5), HANGING 2 s (6-21), recovered (22-30).
 * Phase A without circuit breaker (timeout 0.5 s + fallback), phase B with the breaker.
 */
public class CircuitBreakerDemo {
    static final String CACHE = "{\"O+\":40,\"O-\":3,\"A+\":17,\"source\":\"cache\"}";

    public static DemoReport run(InventoryClient inv, ProtectedCall breaker, String impl) {
        DemoReport r = new DemoReport("circuit-breaker", impl);
        Supplier<String> fetch = () -> InventoryClient.check(inv.get("", Duration.ofMillis(500), null)).body();

        r.line("### A) WITHOUT circuit breaker (timeout 0.5 s + fallback only)");
        Phase a = scenario(inv, r, () -> {
            try { return fetch.get(); } catch (RuntimeException e) { return CACHE; }
        }, () -> "-");
        sleep(2200); // let the hung server threads finish

        r.line("### B) WITH circuit breaker (" + impl + ": 3 failures -> OPEN, 1.5 s -> HALF_OPEN)");
        Phase b = scenario(inv, r, () -> breaker.call(fetch, () -> CACHE), breaker::state);

        r.line(String.format("### Summary: callers waited %.2f s during the outage (calls 6-21) WITHOUT breaker; %d requests reached ms-inventory",
                a.outageMs / 1000.0, a.requests));
        r.line(String.format("### Summary: callers waited %.2f s during the outage (calls 6-21) WITH breaker;    %d requests reached ms-inventory",
                b.outageMs / 1000.0, b.requests));
        r.put("withoutBreakerOutageSeconds", a.outageMs / 1000.0);
        r.put("withBreakerOutageSeconds", b.outageMs / 1000.0);
        r.put("requestsWithoutBreaker", a.requests);
        r.put("requestsWithBreaker", b.requests);
        r.put("latencyMsWithout", a.latencies);
        r.put("latencyMsWith", b.latencies);
        return r;
    }

    record Phase(long outageMs, int requests, List<Long> latencies) { }

    private static Phase scenario(InventoryClient inv, DemoReport r, Supplier<String> call, Supplier<String> state) {
        inv.reset();
        List<Long> lat = new ArrayList<>();
        long outage = 0;
        for (int i = 1; i <= 30; i++) {
            if (i == 6) { inv.setMode("hang"); r.line("   -- ms-inventory starts hanging --"); }
            if (i == 22) { inv.setMode("ok"); r.line("   -- ms-inventory recovered --"); }
            long t = System.nanoTime();
            String body = call.get();
            long ms = (System.nanoTime() - t) / 1_000_000;
            lat.add(ms);
            if (i >= 6 && i <= 21) { outage += ms; }
            r.line(String.format("call %2d %6d ms  state=%-9s source=%s", i, ms, state.get(),
                    body.contains("\"cache\"") ? "cache (fallback)" : "live"));
            sleep(250);
        }
        int requests = Integer.parseInt(inv.stats().replaceAll(".*\"requests\":(\\d+).*", "$1"));
        return new Phase(outage, requests, lat);
    }

    static void sleep(long ms) {
        try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
    }
}
