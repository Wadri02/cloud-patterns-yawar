package ec.edu.uce.yawar.requests.resilience;

import java.util.function.DoubleSupplier;
import java.util.function.LongConsumer;
import java.util.function.Supplier;

/**
 * Retry with exponential backoff + FULL JITTER, max attempts, selective retry and Retry-After support.
 *   delay(attempt) = random(0, min(cap, base * 2^attempt))
 * Only RetryableException is retried; anything else (e.g. a 400) propagates immediately.
 */
public class Retry {
    public interface Listener { void onRetry(int attempt, long delayMs, RuntimeException cause); }

    private final int maxAttempts;
    private final long baseMs;
    private final long capMs;
    private final boolean jitter;
    private final DoubleSupplier random;
    private final LongConsumer sleeper;
    private final Listener listener;

    public Retry(int maxAttempts, long baseMs, long capMs, boolean jitter,
                 DoubleSupplier random, LongConsumer sleeper, Listener listener) {
        this.maxAttempts = maxAttempts;
        this.baseMs = baseMs;
        this.capMs = capMs;
        this.jitter = jitter;
        this.random = random;
        this.sleeper = sleeper;
        this.listener = listener == null ? (a, d, c) -> { } : listener;
    }

    public Retry(int maxAttempts, long baseMs, long capMs, Listener listener) {
        this(maxAttempts, baseMs, capMs, true, Math::random, Retry::sleep, listener);
    }

    public static long backoff(int attempt, long baseMs, long capMs, boolean jitter, double random) {
        long exp = Math.min(capMs, baseMs * (1L << Math.min(attempt, 30)));
        return jitter ? (long) (random * exp) : exp;
    }

    public <T> T execute(Supplier<T> fn) {
        for (int attempt = 0; ; attempt++) {
            try {
                return fn.get();
            } catch (RetryableException e) {
                if (attempt == maxAttempts - 1) {
                    throw new RetriesExhaustedException("gave up after " + maxAttempts + " attempts: " + e.getMessage(), e);
                }
                long delay = backoff(attempt, baseMs, capMs, jitter, random.getAsDouble());
                if (e.retryAfterMs() != null) { delay = Math.max(delay, e.retryAfterMs()); }
                listener.onRetry(attempt + 1, delay, e);
                sleeper.accept(delay);
            }
        }
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }
}
