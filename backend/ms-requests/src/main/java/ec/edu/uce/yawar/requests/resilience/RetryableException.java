package ec.edu.uce.yawar.requests.resilience;

/** Transient failure (5xx, 429, connection error, timeout). retryAfterMs comes from Retry-After when present. */
public class RetryableException extends RuntimeException {
    private final Long retryAfterMs;

    public RetryableException(String message, Long retryAfterMs) {
        super(message);
        this.retryAfterMs = retryAfterMs;
    }

    public RetryableException(String message) { this(message, null); }

    public Long retryAfterMs() { return retryAfterMs; }
}
