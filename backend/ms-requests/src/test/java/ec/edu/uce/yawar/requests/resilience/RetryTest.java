package ec.edu.uce.yawar.requests.resilience;

import static org.junit.jupiter.api.Assertions.*;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

class RetryTest {
    private final List<Long> sleeps = new ArrayList<>();

    private Retry retry(int attempts) {
        return new Retry(attempts, 100, 1000, true, () -> 0.5, sleeps::add, null);
    }

    @Test
    void succeedsAfterTransientFailures() {
        AtomicInteger calls = new AtomicInteger();
        String r = retry(4).execute(() -> {
            if (calls.incrementAndGet() < 3) { throw new RetryableException("503"); }
            return "ok";
        });
        assertEquals("ok", r);
        assertEquals(3, calls.get());
        assertEquals(2, sleeps.size());
    }

    @Test
    void givesUpAfterMaxAttempts() {
        AtomicInteger calls = new AtomicInteger();
        assertThrows(RetriesExhaustedException.class, () -> retry(3).execute(() -> {
            calls.incrementAndGet();
            throw new RetryableException("503");
        }));
        assertEquals(3, calls.get());
    }

    @Test
    void nonRetryableErrorIsNotRetried() {
        AtomicInteger calls = new AtomicInteger();
        assertThrows(IllegalArgumentException.class, () -> retry(4).execute(() -> {
            calls.incrementAndGet();
            throw new IllegalArgumentException("400");
        }));
        assertEquals(1, calls.get());
    }

    @Test
    void backoffGrowsAndIsCapped() {
        long[] expected = {100, 200, 400, 800, 1000, 1000};
        for (int a = 0; a < expected.length; a++) {
            assertEquals(expected[a], Retry.backoff(a, 100, 1000, false, 0));
        }
    }

    @Test
    void fullJitterStaysWithinBounds() {
        for (int a = 0; a < 6; a++) {
            for (int i = 0; i < 100; i++) {
                long d = Retry.backoff(a, 100, 1000, true, Math.random());
                assertTrue(d >= 0 && d <= Math.min(1000, 100L << a));
            }
        }
    }

    @Test
    void retryAfterIsRespected() {
        AtomicInteger calls = new AtomicInteger();
        retry(2).execute(() -> {
            if (calls.incrementAndGet() == 1) { throw new RetryableException("429", 1500L); }
            return "ok";
        });
        assertEquals(List.of(1500L), sleeps);
    }
}
