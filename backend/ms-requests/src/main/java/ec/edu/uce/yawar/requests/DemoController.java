package ec.edu.uce.yawar.requests;

import ec.edu.uce.yawar.requests.client.InventoryClient;
import ec.edu.uce.yawar.requests.demo.*;
import ec.edu.uce.yawar.requests.r4j.Resilience4jAdapters;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * Demo endpoints (one per pattern). impl=custom uses our implementation, impl=resilience4j the library.
 *   GET /api/requests/demo/circuit-breaker?impl=custom|resilience4j   (~30 s)
 *   GET /api/requests/demo/retry?impl=custom|resilience4j             (~3 s)
 *   GET /api/requests/demo/timeout?impl=custom|resilience4j           (~15 s)
 *   GET /api/requests/stock   -> business call protected with Resilience4j annotations
 */
@RestController
@RequestMapping("/api/requests")
public class DemoController {
    private final InventoryClient inventory;
    private final StockService stock;

    public DemoController(InventoryClient inventory, StockService stock) {
        this.inventory = inventory;
        this.stock = stock;
    }

    private static boolean r4j(String impl) {
        if (!impl.equals("custom") && !impl.equals("resilience4j")) {
            throw new IllegalArgumentException("impl must be custom or resilience4j");
        }
        return impl.equals("resilience4j");
    }

    @GetMapping("/demo/circuit-breaker")
    public Map<String, Object> circuitBreaker(@RequestParam(defaultValue = "custom") String impl) {
        ProtectedCall cb = r4j(impl) ? Resilience4jAdapters.circuitBreaker() : CustomAdapters.circuitBreaker();
        return CircuitBreakerDemo.run(inventory, cb, impl).toMap();
    }

    @GetMapping("/demo/retry")
    public Map<String, Object> retry(@RequestParam(defaultValue = "custom") String impl) {
        return RetryDemo.run(inventory, r4j(impl) ? Resilience4jAdapters::retry : CustomAdapters::retry, impl).toMap();
    }

    @GetMapping("/demo/timeout")
    public Map<String, Object> timeout(@RequestParam(defaultValue = "custom") String impl) throws Exception {
        TimeLimit tl = r4j(impl) ? Resilience4jAdapters.timeLimiter() : CustomAdapters.timeLimiter();
        return TimeoutDemo.run(inventory, tl, impl).toMap();
    }

    @GetMapping(value = "/stock", produces = MediaType.APPLICATION_JSON_VALUE)
    public CompletableFuture<String> stock() {
        return stock.currentStock();
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, String>> badRequest(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }
}
