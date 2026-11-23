package ec.edu.uce.yawar.donors;

import java.net.InetAddress;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/donors")
public class DonorController {
    private static final Logger log = LoggerFactory.getLogger(DonorController.class);
    private static final List<Donor> DONORS = List.of(
            new Donor("D-001", "Ana Quishpe", "O+", "Quito"),
            new Donor("D-002", "Luis Andrade", "A-", "Ambato"),
            new Donor("D-003", "Carla Yépez", "B+", "Ibarra"));

    private final ChaosState chaos;
    private final String instance;

    public DonorController(ChaosState chaos) throws Exception {
        this.chaos = chaos;
        // In ECS the hostname is unique per task (ip-10-0-x-y...), locally it is the container id
        this.instance = System.getenv().getOrDefault("INSTANCE", InetAddress.getLocalHost().getHostName());
    }

    @GetMapping
    public ResponseEntity<Map<String, Object>> list(@RequestHeader(value = "X-Request-ID", required = false) String reqId) {
        if (chaos.isFailing()) {
            return ResponseEntity.status(503).header("X-Instance", instance).body(Map.of("error", "replica failing", "instance", instance));
        }
        log.info("GET /api/donors instance={} reqId={}", instance, reqId);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("service", "ms-donors");
        body.put("instance", instance);
        body.put("data", DONORS);
        return ResponseEntity.ok().header("X-Instance", instance).body(body);
    }

    /** POST /api/donors/chaos?mode=fail|ok - only the replica that receives the call is affected. */
    @PostMapping("/chaos")
    public Map<String, String> chaos(@RequestParam String mode) {
        chaos.setFailing("fail".equals(mode));
        log.warn("chaos mode={} on instance={}", mode, instance);
        return Map.of("instance", instance, "mode", mode);
    }
}
