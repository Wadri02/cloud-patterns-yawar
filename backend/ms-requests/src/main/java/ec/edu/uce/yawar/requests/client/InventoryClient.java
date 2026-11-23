package ec.edu.uce.yawar.requests.client;

import ec.edu.uce.yawar.requests.resilience.RetryableException;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpTimeoutException;
import java.time.Duration;
import java.util.Map;

/**
 * HTTP client for ms-inventory (java.net.http). Every call takes an explicit timeout:
 * connect timeout is fixed on the client, the per-request timeout bounds the whole response.
 * In AWS INVENTORY_URL points to the ALB (http://<alb>/api/inventory); locally to the container.
 */
public class InventoryClient {
    public record Result(int status, String body, Long retryAfterMs) {
        public boolean ok() { return status >= 200 && status < 300; }
    }

    private final String baseUrl;
    private final HttpClient http;

    public InventoryClient(String baseUrl, Duration connectTimeout) {
        this.baseUrl = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
        this.http = HttpClient.newBuilder().connectTimeout(connectTimeout).version(HttpClient.Version.HTTP_1_1).build();
    }

    public String baseUrl() { return baseUrl; }

    /** timeout == null means "wait forever" (used only to show why that is a bad idea). */
    public Result get(String path, Duration timeout, Map<String, String> headers) {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(baseUrl + path)).GET();
        return send(b, timeout, headers);
    }

    public Result post(String path, String json, Duration timeout, Map<String, String> headers) {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(baseUrl + path))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(json));
        return send(b, timeout, headers);
    }

    private Result send(HttpRequest.Builder b, Duration timeout, Map<String, String> headers) {
        if (timeout != null) { b.timeout(timeout); }
        if (headers != null) { headers.forEach(b::header); }
        try {
            HttpResponse<String> r = http.send(b.build(), HttpResponse.BodyHandlers.ofString());
            Long retryAfter = r.headers().firstValue("Retry-After").map(v -> Long.parseLong(v) * 1000).orElse(null);
            return new Result(r.statusCode(), r.body(), retryAfter);
        } catch (HttpTimeoutException e) {
            throw new RetryableException("timeout: " + e.getMessage());
        } catch (IOException e) {
            throw new RetryableException("I/O error: " + e.getClass().getSimpleName());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }

    /** Maps HTTP status to the resilience vocabulary: 5xx/429 transient, other 4xx permanent. */
    public static Result check(Result r) {
        if (r.status() >= 500 || r.status() == 429) {
            throw new RetryableException("HTTP " + r.status(), r.retryAfterMs());
        }
        if (r.status() >= 400) {
            throw new IllegalArgumentException("HTTP " + r.status() + " " + r.body());
        }
        return r;
    }

    // ---- admin helpers for the demos -------------------------------------------------------
    public void setMode(String mode) { post("/admin/mode?mode=" + mode, "", Duration.ofSeconds(5), null); }

    public String reset() { return post("/admin/reset", "", Duration.ofSeconds(5), null).body(); }

    public String stats() { return get("/admin/stats", Duration.ofSeconds(5), null).body(); }
}
