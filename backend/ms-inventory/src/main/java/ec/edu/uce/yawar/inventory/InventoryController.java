package ec.edu.uce.yawar.inventory;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/inventory")
public class InventoryController {
    private static final Logger log = LoggerFactory.getLogger(InventoryController.class);
    private final FailureMode failure;
    private final List<Map<String, Object>> donations = new CopyOnWriteArrayList<>();
    private final Map<String, Map<String, Object>> idempotency = new ConcurrentHashMap<>();

    public InventoryController(FailureMode failure) {
        this.failure = failure;
    }

    @GetMapping
    public ResponseEntity<Map<String, Object>> stock() throws InterruptedException {
        failure.countRequest();
        if (failure.shouldFailRead()) {
            return ResponseEntity.status(503).header("Retry-After", "0").body(Map.of("error", "ms-inventory unavailable"));
        }
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("O+", 42);
        body.put("O-", 3);
        body.put("A+", 18);
        body.put("source", "live");
        return ResponseEntity.ok(body);
    }

    /** Always 400: used to prove that client errors are NOT retried. */
    @GetMapping("/bad")
    public ResponseEntity<Map<String, Object>> bad() {
        failure.countRequest();
        return ResponseEntity.badRequest().body(Map.of("error", "invalid blood type"));
    }

    /** Registers a donation. Honours Idempotency-Key so a retried request is not stored twice. */
    @PostMapping("/donations")
    public ResponseEntity<Map<String, Object>> donate(@RequestBody Map<String, Object> body,
                                                      @RequestHeader(value = "Idempotency-Key", required = false) String key) {
        failure.countRequest();
        synchronized (this) {
            if (key != null && idempotency.containsKey(key)) {
                Map<String, Object> replay = new LinkedHashMap<>(idempotency.get(key));
                replay.put("replayed", true);
                return ResponseEntity.ok(replay);
            }
            Map<String, Object> record = new LinkedHashMap<>();
            record.put("donationId", String.format("DON-%04d", donations.size() + 1));
            record.putAll(body);
            donations.add(record);
            if (key != null) { idempotency.put(key, record); }
            if (failure.shouldLoseResponse()) {
                log.warn("donation {} stored but response lost", record.get("donationId"));
                return ResponseEntity.status(503).body(Map.of("error", "response lost"));
            }
            return ResponseEntity.status(201).body(record);
        }
    }

    /** Does workMs of work, unless the caller's remaining deadline (X-Deadline-Ms) is too short. */
    @GetMapping("/report")
    public ResponseEntity<Map<String, Object>> report(@RequestParam(defaultValue = "100") int workMs,
                                                      @RequestHeader(value = "X-Deadline-Ms", required = false) Integer budget)
            throws InterruptedException {
        failure.countRequest();
        if (budget != null && workMs > budget) {
            return ResponseEntity.status(504).body(Map.of("error", "deadline too short", "budgetMs", budget, "neededMs", workMs));
        }
        Thread.sleep(workMs);
        return ResponseEntity.ok(Map.of("report", "ok", "workMs", workMs));
    }

    // ---- admin endpoints used by the demos -------------------------------------------------
    @PostMapping("/admin/mode")
    public Map<String, Object> setMode(@RequestParam String mode) {
        failure.set(mode);
        log.warn("failure mode set to {}", mode);
        return Map.of("mode", failure.describe());
    }

    @GetMapping("/admin/stats")
    public Map<String, Object> stats() {
        return Map.of("mode", failure.describe(), "requests", failure.requests(), "donationsStored", donations.size());
    }

    @PostMapping("/admin/reset")
    public Map<String, Object> reset() {
        failure.set("ok");
        failure.resetRequests();
        donations.clear();
        idempotency.clear();
        return stats();
    }
}
