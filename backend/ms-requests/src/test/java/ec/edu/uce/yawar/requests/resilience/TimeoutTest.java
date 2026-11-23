package ec.edu.uce.yawar.requests.resilience;

import static org.junit.jupiter.api.Assertions.*;

import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;

class TimeoutTest {
    @Test
    void fastCallReturnsValue() {
        assertEquals(42, Timeouts.call(() -> 42, 500));
    }

    @Test
    void slowCallIsAbandonedQuickly() {
        long t = System.nanoTime();
        assertThrows(Timeouts.TimeoutExceededException.class, () -> Timeouts.call(() -> {
            try { Thread.sleep(2000); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
            return "late";
        }, 100));
        assertTrue((System.nanoTime() - t) / 1_000_000 < 500);
    }

    @Test
    void deadlineCountsDownAndExpires() {
        AtomicLong now = new AtomicLong();
        Deadline d = new Deadline(1000, now::get);
        now.set(400);
        assertEquals(600, d.remainingMs());
        now.set(1200);
        assertTrue(d.expired());
        assertEquals(0, d.remainingMs());
    }
}
