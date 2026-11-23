package ec.edu.uce.yawar.requests.resilience;

import java.util.concurrent.*;
import java.util.function.Supplier;

/** Bounds ANY blocking call (not only HTTP): runs it on a worker and abandons it after the limit. */
public final class Timeouts {
    private static final ExecutorService POOL = Executors.newVirtualThreadPerTaskExecutor();

    private Timeouts() { }

    public static <T> T call(Supplier<T> fn, long timeoutMs) {
        Future<T> f = POOL.submit(fn::get);
        try {
            return f.get(timeoutMs, TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            f.cancel(true);
            throw new TimeoutExceededException("call exceeded " + timeoutMs + " ms");
        } catch (ExecutionException e) {
            throw e.getCause() instanceof RuntimeException re ? re : new IllegalStateException(e.getCause());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }

    public static class TimeoutExceededException extends RuntimeException {
        public TimeoutExceededException(String message) { super(message); }
    }
}
