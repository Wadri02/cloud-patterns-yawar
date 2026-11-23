package ec.edu.uce.yawar.requests.demo;

import ec.edu.uce.yawar.requests.resilience.CircuitBreaker;
import ec.edu.uce.yawar.requests.resilience.Retry;
import ec.edu.uce.yawar.requests.resilience.Timeouts;
import java.util.function.Supplier;

/** Our own implementations exposed through the same strategy interfaces as Resilience4j. */
public final class CustomAdapters {
    private CustomAdapters() { }

    public static ProtectedCall circuitBreaker() {
        CircuitBreaker cb = new CircuitBreaker("inventory", 3, 1500);
        return new ProtectedCall() {
            @Override
            public String call(Supplier<String> fn, Supplier<String> fallback) { return cb.call(fn, fallback); }

            @Override
            public String state() { return cb.state().name(); }
        };
    }

    public static RetryStrategy retry(Retry.Listener listener) {
        Retry retry = new Retry(4, 100, 1000, listener);
        return new RetryStrategy() {
            @Override
            public <T> T execute(Supplier<T> fn) { return retry.execute(fn); }
        };
    }

    public static TimeLimit timeLimiter() {
        return new TimeLimit() {
            @Override
            public <T> T call(Supplier<T> fn, long timeoutMs) { return Timeouts.call(fn, timeoutMs); }
        };
    }
}
