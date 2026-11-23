package ec.edu.uce.yawar.requests.resilience;

import static org.junit.jupiter.api.Assertions.*;

import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;

class CircuitBreakerTest {
    private final AtomicLong now = new AtomicLong();

    private CircuitBreaker breaker(int threshold, long recoveryMs) {
        return new CircuitBreaker("inventory", threshold, recoveryMs, 1, now::get, null);
    }

    private static String boom() { throw new RetryableException("down"); }

    @Test
    void opensAfterThresholdAndShortCircuits() {
        AtomicInteger calls = new AtomicInteger();
        CircuitBreaker cb = breaker(3, 10_000);
        for (int i = 0; i < 3; i++) {
            assertThrows(RetryableException.class, () -> cb.call(() -> { calls.incrementAndGet(); return boom(); }, null));
        }
        assertEquals(CircuitBreaker.State.OPEN, cb.state());
        assertThrows(CircuitOpenException.class, () -> cb.call(() -> { calls.incrementAndGet(); return "x"; }, null));
        assertEquals(3, calls.get(), "4th call must never reach the service");
    }

    @Test
    void fallbackIsUsedWhenOpen() {
        CircuitBreaker cb = breaker(1, 10_000);
        assertEquals("cached", cb.call(CircuitBreakerTest::boom, () -> "cached"));
        assertEquals("cached", cb.call(() -> "live", () -> "cached"));
    }

    @Test
    void halfOpenSuccessCloses() {
        CircuitBreaker cb = breaker(1, 5000);
        cb.call(CircuitBreakerTest::boom, () -> null);
        now.set(5000);
        assertEquals(CircuitBreaker.State.HALF_OPEN, cb.state());
        assertEquals("live", cb.call(() -> "live", null));
        assertEquals(CircuitBreaker.State.CLOSED, cb.state());
    }

    @Test
    void halfOpenFailureReopens() {
        CircuitBreaker cb = breaker(1, 5000);
        cb.call(CircuitBreakerTest::boom, () -> null);
        now.set(6000);
        cb.call(CircuitBreakerTest::boom, () -> null);
        assertEquals(CircuitBreaker.State.OPEN, cb.state());
    }

    @Test
    void successResetsFailureCount() {
        CircuitBreaker cb = breaker(2, 5000);
        cb.call(CircuitBreakerTest::boom, () -> null);
        cb.call(() -> "ok", null);
        cb.call(CircuitBreakerTest::boom, () -> null);
        assertEquals(CircuitBreaker.State.CLOSED, cb.state());
    }
}
