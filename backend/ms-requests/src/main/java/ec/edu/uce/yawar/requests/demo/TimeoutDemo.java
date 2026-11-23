package ec.edu.uce.yawar.requests.demo;

import ec.edu.uce.yawar.requests.client.InventoryClient;
import ec.edu.uce.yawar.requests.resilience.Deadline;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

/**
 * A) hanging dependency, 12 concurrent requests, 4 worker threads: no timeout vs 0.5 s timeout
 * B) connect timeout vs read timeout
 * C) deadline propagation (X-Deadline-Ms) across two hops with a 1000 ms budget
 * D) time limiter around a non-HTTP blocking call
 */
public class TimeoutDemo {
    public static DemoReport run(InventoryClient inv, TimeLimit limiter, String impl) throws Exception {
        DemoReport r = new DemoReport("timeout", impl);
        inv.reset();

        r.line("### A) ms-inventory hangs (2 s). 12 concurrent requests, worker pool of 4 threads");
        inv.setMode("hang");
        double noTimeout = burst(inv, null, r, "no timeout     ");
        CircuitBreakerDemo.sleep(2200);
        double withTimeout = burst(inv, Duration.ofMillis(500), r, "timeout = 0.5 s");
        CircuitBreakerDemo.sleep(2200);

        r.line("### B) connect timeout vs read timeout");
        InventoryClient unreachable = new InventoryClient("http://10.255.255.1:81", Duration.ofMillis(300));
        long t = System.nanoTime();
        try {
            unreachable.get("/", Duration.ofSeconds(5), null);
        } catch (RuntimeException e) {
            r.line(String.format("   unreachable host   -> %s after %d ms", e.getMessage(), (System.nanoTime() - t) / 1_000_000));
        }
        t = System.nanoTime();
        try {
            inv.get("", Duration.ofMillis(800), null);
        } catch (RuntimeException e) {
            r.line(String.format("   connected but slow -> %s after %d ms", e.getMessage(), (System.nanoTime() - t) / 1_000_000));
        }
        inv.setMode("ok");
        CircuitBreakerDemo.sleep(2200);

        r.line("### C) deadline propagation: the gateway gives the whole request a 1000 ms budget");
        r.line("  without propagation:");
        long without = handle(inv, r, false);
        CircuitBreakerDemo.sleep(1000);
        r.line("  with X-Deadline-Ms propagation:");
        long with = handle(inv, r, true);

        r.line("### D) " + impl + " time limiter around a slow non-HTTP call (simulated SQL query 1.5 s, limit 300 ms)");
        t = System.nanoTime();
        try {
            limiter.call(() -> { CircuitBreakerDemo.sleep(1500); return "rows"; }, 300);
        } catch (RuntimeException e) {
            r.line(String.format("   %s: %s; caller released after %d ms", e.getClass().getSimpleName(), e.getMessage(),
                    (System.nanoTime() - t) / 1_000_000));
        }

        r.put("burstNoTimeoutSeconds", noTimeout);
        r.put("burstWithTimeoutSeconds", withTimeout);
        r.put("deadlineWithoutPropagationMs", without);
        r.put("deadlineWithPropagationMs", with);
        inv.reset();
        return r;
    }

    private static double burst(InventoryClient inv, Duration timeout, DemoReport r, String label) throws Exception {
        long t = System.nanoTime();
        ExecutorService pool = Executors.newFixedThreadPool(4);
        List<Future<String>> fs = new ArrayList<>();
        for (int i = 0; i < 12; i++) {
            fs.add(pool.submit(() -> {
                try {
                    return inv.get("", timeout, null).ok() ? "live" : "error";
                } catch (RuntimeException e) {
                    return "fallback";
                }
            }));
        }
        TreeSet<String> results = new TreeSet<>();
        for (Future<String> f : fs) { results.add(f.get()); }
        pool.shutdown();
        double s = (System.nanoTime() - t) / 1e9;
        r.line(String.format("   %s: all 12 answered after %5.2f s   results=%s", label, s, results));
        return s;
    }

    private static long handle(InventoryClient inv, DemoReport r, boolean propagate) {
        Deadline d = new Deadline(1000);
        long t = System.nanoTime();
        InventoryClient.Result r1 = inv.get("/report?workMs=400", Duration.ofMillis(d.remainingMs()),
                Map.of("X-Deadline-Ms", String.valueOf(d.remainingMs())));
        r.line("   step 1 ms-inventory -> " + r1.status() + " (remaining budget " + d.remainingMs() + " ms)");
        long t2 = System.nanoTime();
        try {
            Map<String, String> h = propagate ? Map.of("X-Deadline-Ms", String.valueOf(d.remainingMs())) : Map.of();
            InventoryClient.Result r2 = inv.get("/report?workMs=800", Duration.ofMillis(Math.max(1, d.remainingMs())), h);
            r.line("   step 2 ms-analytics -> " + r2.status() + " " + r2.body() + " in " + (System.nanoTime() - t2) / 1_000_000 + " ms");
        } catch (RuntimeException e) {
            r.line("   step 2 ms-analytics -> caller timed out after " + (System.nanoTime() - t2) / 1_000_000
                    + " ms (the server kept working 800 ms for nobody)");
        }
        long total = (System.nanoTime() - t) / 1_000_000;
        r.line("   total " + total + " ms");
        return total;
    }
}
