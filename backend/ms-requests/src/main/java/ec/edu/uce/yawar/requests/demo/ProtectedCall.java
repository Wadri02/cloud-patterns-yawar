package ec.edu.uce.yawar.requests.demo;

import java.util.function.Supplier;

/** A circuit-breaker strategy. Two implementations: our own and Resilience4j. */
public interface ProtectedCall {
    String call(Supplier<String> fn, Supplier<String> fallback);

    String state();
}
