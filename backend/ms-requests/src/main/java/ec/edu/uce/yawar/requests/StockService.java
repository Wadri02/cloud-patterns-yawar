package ec.edu.uce.yawar.requests;

import ec.edu.uce.yawar.requests.client.InventoryClient;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import io.github.resilience4j.timelimiter.annotation.TimeLimiter;
import java.time.Duration;
import java.util.concurrent.CompletableFuture;
import org.springframework.stereotype.Service;

/**
 * How Yawar protects a real call in production: Resilience4j annotations (resilience4j-spring-boot4)
 * configured in application.yml.
 * Execution order: Retry( CircuitBreaker( TimeLimiter( call ) ) ).
 */
@Service
public class StockService {
    private final InventoryClient client;

    public StockService(InventoryClient client) {
        this.client = client;
    }

    @Retry(name = "inventory")
    @CircuitBreaker(name = "inventory", fallbackMethod = "cachedStock")
    @TimeLimiter(name = "inventory")
    public CompletableFuture<String> currentStock() {
        return CompletableFuture.supplyAsync(() -> InventoryClient.check(client.get("", Duration.ofSeconds(3), null)).body());
    }

    public CompletableFuture<String> cachedStock(Throwable cause) {
        return CompletableFuture.completedFuture(
                "{\"O+\":40,\"O-\":3,\"A+\":17,\"source\":\"cache\",\"reason\":\"" + cause.getClass().getSimpleName() + "\"}");
    }
}
