package ec.edu.uce.yawar.requests.demo;

import java.util.function.Supplier;

/** A time-limiter strategy. Two implementations: our own (Timeouts) and Resilience4j TimeLimiter. */
public interface TimeLimit {
    <T> T call(Supplier<T> fn, long timeoutMs);
}
