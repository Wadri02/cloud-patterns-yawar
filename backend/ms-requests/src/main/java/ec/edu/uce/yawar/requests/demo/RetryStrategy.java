package ec.edu.uce.yawar.requests.demo;

import java.util.function.Supplier;

/** A retry strategy. Two implementations: our own and Resilience4j. */
public interface RetryStrategy {
    <T> T execute(Supplier<T> fn);
}
