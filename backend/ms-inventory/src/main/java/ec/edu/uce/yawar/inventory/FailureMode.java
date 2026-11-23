package ec.edu.uce.yawar.inventory;

import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.stereotype.Component;

/**
 * Runtime failure modes:
 *   ok        -> normal
 *   down      -> 503 immediately
 *   hang      -> waits 2 s before answering (stuck / overloaded)
 *   flaky:N   -> next N GET requests answer 503, then ok (transient fault)
 *   lost:N    -> next N POST donations are STORED but answer 503 (response lost)
 */
@Component
public class FailureMode {
    private String mode = "ok";
    private int remaining = 0;
    private final AtomicInteger requests = new AtomicInteger();

    public synchronized void set(String value) {
        if (value.startsWith("flaky:") || value.startsWith("lost:")) {
            String[] p = value.split(":");
            mode = p[0];
            remaining = Integer.parseInt(p[1]);
        } else if (value.equals("ok") || value.equals("down") || value.equals("hang")) {
            mode = value;
            remaining = 0;
        } else {
            throw new IllegalArgumentException("mode must be ok|down|hang|flaky:N|lost:N");
        }
    }

    public synchronized String describe() {
        return remaining > 0 ? mode + ":" + remaining : mode;
    }

    public int countRequest() { return requests.incrementAndGet(); }

    public int requests() { return requests.get(); }

    public void resetRequests() { requests.set(0); }

    /** For GET requests: returns true if this request must fail; may block when hanging. */
    public boolean shouldFailRead() throws InterruptedException {
        String current;
        synchronized (this) {
            if (mode.equals("flaky")) {
                if (--remaining <= 0) { mode = "ok"; }
                return true;
            }
            current = mode;
        }
        if (current.equals("down")) { return true; }
        if (current.equals("hang")) { Thread.sleep(2000); }
        return false;
    }

    /** For POST requests: returns true if the response must be "lost" (data is stored anyway). */
    public synchronized boolean shouldLoseResponse() {
        if (mode.equals("lost")) {
            if (--remaining <= 0) { mode = "ok"; }
            return true;
        }
        return false;
    }
}
