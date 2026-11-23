package ec.edu.uce.yawar.requests.resilience;

import java.util.function.BiConsumer;
import java.util.function.LongSupplier;
import java.util.function.Supplier;

/**
 * Circuit Breaker written from scratch (thread-safe, no dependencies).
 *
 * CLOSED    -> calls pass; consecutive failures are counted
 * OPEN      -> calls are rejected immediately (CircuitOpenException) and the fallback is used
 * HALF_OPEN -> after recoveryTimeoutMs, up to halfOpenMaxCalls trial calls pass:
 *              success -> CLOSED, failure -> OPEN again
 */
public class CircuitBreaker {
    public enum State { CLOSED, OPEN, HALF_OPEN }

    private final String name;
    private final int failureThreshold;
    private final long recoveryTimeoutMs;
    private final int halfOpenMaxCalls;
    private final LongSupplier clock;
    private final BiConsumer<State, State> onStateChange;

    private State state = State.CLOSED;
    private int failures;
    private long openedAt;
    private int halfOpenCalls;

    public CircuitBreaker(String name, int failureThreshold, long recoveryTimeoutMs, int halfOpenMaxCalls,
                          LongSupplier clockMs, BiConsumer<State, State> onStateChange) {
        this.name = name;
        this.failureThreshold = failureThreshold;
        this.recoveryTimeoutMs = recoveryTimeoutMs;
        this.halfOpenMaxCalls = halfOpenMaxCalls;
        this.clock = clockMs;
        this.onStateChange = onStateChange == null ? (a, b) -> { } : onStateChange;
    }

    public CircuitBreaker(String name, int failureThreshold, long recoveryTimeoutMs) {
        this(name, failureThreshold, recoveryTimeoutMs, 1, System::currentTimeMillis, null);
    }

    public synchronized State state() {
        maybeHalfOpen();
        return state;
    }

    private void transition(State next) {
        State old = state;
        state = next;
        if (old != next) { onStateChange.accept(old, next); }
    }

    private void maybeHalfOpen() {
        if (state == State.OPEN && clock.getAsLong() - openedAt >= recoveryTimeoutMs) {
            transition(State.HALF_OPEN);
            halfOpenCalls = 0;
        }
    }

    private synchronized void beforeCall() {
        maybeHalfOpen();
        if (state == State.OPEN) {
            throw new CircuitOpenException("circuit '" + name + "' is OPEN");
        }
        if (state == State.HALF_OPEN) {
            if (halfOpenCalls >= halfOpenMaxCalls) {
                throw new CircuitOpenException("circuit '" + name + "' is HALF_OPEN (trial in progress)");
            }
            halfOpenCalls++;
        }
    }

    private synchronized void onSuccess() {
        failures = 0;
        transition(State.CLOSED);
    }

    private synchronized void onFailure() {
        failures++;
        if (state == State.HALF_OPEN || failures >= failureThreshold) {
            openedAt = clock.getAsLong();
            transition(State.OPEN);
        }
    }

    /** Runs the call through the breaker; uses the fallback when OPEN or when the call fails. */
    public <T> T call(Supplier<T> fn, Supplier<T> fallback) {
        try {
            beforeCall();
        } catch (CircuitOpenException e) {
            if (fallback != null) { return fallback.get(); }
            throw e;
        }
        try {
            T result = fn.get();
            onSuccess();
            return result;
        } catch (RuntimeException e) {
            onFailure();
            if (fallback != null) { return fallback.get(); }
            throw e;
        }
    }
}
