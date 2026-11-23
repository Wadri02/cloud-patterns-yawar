package ec.edu.uce.yawar.requests.demo;

import ec.edu.uce.yawar.requests.client.InventoryClient;
import ec.edu.uce.yawar.requests.resilience.Retry;
import java.time.Duration;
import java.util.Map;
import java.util.Random;
import java.util.UUID;
import java.util.function.Function;

/**
 * A) transient 503 x2 -> success   B) 400 -> not retried   C) permanent outage -> gives up
 * D) POST with lost response: duplicates without Idempotency-Key, none with it
 * E) 200 clients retrying at once: peak load without vs with jitter (simulation)
 */
public class RetryDemo {
    public static DemoReport run(InventoryClient inv, Function<Retry.Listener, RetryStrategy> factory, String impl) {
        DemoReport r = new DemoReport("retry", impl);
        RetryStrategy retry = factory.apply((n, delay, e) ->
                r.line(String.format("   attempt %d failed (%s); retrying in %d ms", n, e.getMessage(), delay)));

        inv.reset();
        r.line("### A) transient failure: next 2 requests return 503");
        inv.setMode("flaky:2");
        long t = System.nanoTime();
        String body = retry.execute(() -> InventoryClient.check(inv.get("", Duration.ofSeconds(2), null)).body());
        r.line("   result: " + body + "  (" + (System.nanoTime() - t) / 1_000_000 + " ms, requests sent: " + requests(inv) + ")");

        inv.reset();
        r.line("### B) client error 400 is NOT retried");
        try {
            retry.execute(() -> InventoryClient.check(inv.get("/bad", Duration.ofSeconds(2), null)).body());
        } catch (IllegalArgumentException e) {
            r.line("   failed fast: " + e.getMessage() + "  (requests sent: " + requests(inv) + ")");
        }

        inv.reset();
        r.line("### C) permanent outage");
        inv.setMode("down");
        try {
            retry.execute(() -> InventoryClient.check(inv.get("", Duration.ofSeconds(2), null)).body());
        } catch (RuntimeException e) {
            r.line("   " + e.getClass().getSimpleName() + ": " + e.getMessage() + "  (requests sent: " + requests(inv) + ")");
        }
        int afterC = requests(inv);

        String donation = "{\"donor\":\"D-001\",\"bloodType\":\"O+\",\"center\":\"HCAM\"}";
        inv.reset();
        r.line("### D1) POST donation, response lost once, NO Idempotency-Key");
        inv.setMode("lost:1");
        r.line("   result: " + retry.execute(() -> InventoryClient.check(inv.post("/donations", donation, Duration.ofSeconds(2), null)).body()));
        int dupStored = stored(inv);
        r.line("   donations stored: " + dupStored + "   <-- DUPLICATE created by the retry");

        inv.reset();
        r.line("### D2) same failure WITH Idempotency-Key");
        inv.setMode("lost:1");
        String key = UUID.randomUUID().toString();
        r.line("   Idempotency-Key: " + key);
        r.line("   result: " + retry.execute(() -> InventoryClient.check(
                inv.post("/donations", donation, Duration.ofSeconds(2), Map.of("Idempotency-Key", key))).body()));
        int safeStored = stored(inv);
        r.line("   donations stored: " + safeStored + "   <-- safe retry, no duplicate");

        r.line("### E) simulation: 200 clients fail at t=0 and retry 4 times (base 400 ms, cap 3.2 s), 100 ms windows");
        int peakNone = peak(false);
        int peakFull = peak(true);
        r.line("   no jitter  : peak " + peakNone + " requests in one window");
        r.line("   full jitter: peak " + peakFull + " requests in one window");

        r.put("permanentOutageRequests", afterC);
        r.put("donationsWithoutKey", dupStored);
        r.put("donationsWithKey", safeStored);
        r.put("peakNoJitter", peakNone);
        r.put("peakFullJitter", peakFull);
        inv.reset();
        return r;
    }

    static int peak(boolean jitter) {
        Random rnd = new Random(7);
        int[] buckets = new int[60];
        for (int c = 0; c < 200; c++) {
            long t = 0;
            for (int attempt = 0; attempt < 4; attempt++) {
                t += Retry.backoff(attempt, 400, 3200, jitter, rnd.nextDouble());
                if (t < 6000) { buckets[(int) (t / 100)]++; }
            }
        }
        int max = 0;
        for (int b : buckets) { max = Math.max(max, b); }
        return max;
    }

    private static int requests(InventoryClient inv) {
        return Integer.parseInt(inv.stats().replaceAll(".*\"requests\":(\\d+).*", "$1"));
    }

    private static int stored(InventoryClient inv) {
        return Integer.parseInt(inv.stats().replaceAll(".*\"donationsStored\":(\\d+).*", "$1"));
    }
}
