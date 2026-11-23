package ec.edu.uce.yawar.requests.r4j;

import ec.edu.uce.yawar.requests.demo.ProtectedCall;
import ec.edu.uce.yawar.requests.demo.RetryStrategy;
import ec.edu.uce.yawar.requests.demo.TimeLimit;
import ec.edu.uce.yawar.requests.resilience.RetryableException;
import ec.edu.uce.yawar.requests.resilience.Timeouts;
import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import io.github.resilience4j.core.IntervalFunction;
import io.github.resilience4j.retry.Retry;
import io.github.resilience4j.retry.RetryConfig;
import io.github.resilience4j.timelimiter.TimeLimiter;
import io.github.resilience4j.timelimiter.TimeLimiterConfig;
import java.time.Duration;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeoutException;
import java.util.function.Supplier;

/** Resilience4j versions of the three strategies, configured like our own implementations. */
public final class Resilience4jAdapters {
    private Resilience4jAdapters() { }

    /** 3 failed calls -> OPEN, 1.5 s -> HALF_OPEN with 1 trial call (same as the custom breaker). */
    public static ProtectedCall circuitBreaker() {
        CircuitBreakerConfig cfg = CircuitBreakerConfig.custom()
                .slidingWindowType(CircuitBreakerConfig.SlidingWindowType.COUNT_BASED)
                .slidingWindowSize(3)
                .minimumNumberOfCalls(3)
                .failureRateThreshold(100)
                .waitDurationInOpenState(Duration.ofMillis(1500))
                .permittedNumberOfCallsInHalfOpenState(1)
                .build();
        CircuitBreaker cb = CircuitBreaker.of("inventory-demo-" + UUID.randomUUID(), cfg);
        return new ProtectedCall() {
            @Override
            public String call(Supplier<String> fn, Supplier<String> fallback) {
                try {
                    return cb.executeSupplier(fn);
                } catch (CallNotPermittedException e) {
                    return fallback.get();
                } catch (RuntimeException e) {
                    return fallback.get();
                }
            }

            @Override
            public String state() { return cb.getState().name(); }
        };
    }

    /** 4 attempts, exponential backoff from 100 ms (x2) with randomization, only RetryableException. */
    public static RetryStrategy retry(ec.edu.uce.yawar.requests.resilience.Retry.Listener listener) {
        RetryConfig cfg = RetryConfig.custom()
                .maxAttempts(4)
                .intervalFunction(IntervalFunction.ofExponentialRandomBackoff(Duration.ofMillis(100), 2.0, 0.5))
                .retryExceptions(RetryableException.class)
                .build();
        Retry retry = Retry.of("inventory-demo-" + UUID.randomUUID(), cfg);
        retry.getEventPublisher().onRetry(ev -> listener.onRetry(ev.getNumberOfRetryAttempts(),
                ev.getWaitInterval().toMillis(), (RuntimeException) ev.getLastThrowable()));
        return new RetryStrategy() {
            @Override
            public <T> T execute(Supplier<T> fn) { return retry.executeSupplier(fn); }
        };
    }

    public static TimeLimit timeLimiter() {
        return new TimeLimit() {
            @Override
            public <T> T call(Supplier<T> fn, long timeoutMs) {
                TimeLimiter tl = TimeLimiter.of("inventory-demo", TimeLimiterConfig.custom()
                        .timeoutDuration(Duration.ofMillis(timeoutMs)).cancelRunningFuture(true).build());
                try {
                    return tl.executeFutureSupplier(() -> CompletableFuture.supplyAsync(fn));
                } catch (TimeoutException e) {
                    throw new Timeouts.TimeoutExceededException("resilience4j TimeLimiter: " + e.getMessage());
                } catch (RuntimeException e) {
                    throw e;
                } catch (Exception e) {
                    throw new IllegalStateException(e);
                }
            }
        };
    }
}
