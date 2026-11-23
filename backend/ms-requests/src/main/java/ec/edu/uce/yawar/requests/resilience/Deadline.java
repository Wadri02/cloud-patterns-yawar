package ec.edu.uce.yawar.requests.resilience;

import java.util.function.LongSupplier;

/** A total time budget for a request that crosses several services (propagated as X-Deadline-Ms). */
public class Deadline {
    private final LongSupplier clock;
    private final long end;

    public Deadline(long budgetMs, LongSupplier clockMs) {
        this.clock = clockMs;
        this.end = clockMs.getAsLong() + budgetMs;
    }

    public Deadline(long budgetMs) { this(budgetMs, System::currentTimeMillis); }

    public long remainingMs() { return Math.max(0, end - clock.getAsLong()); }

    public boolean expired() { return remainingMs() == 0; }
}
