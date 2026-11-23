package ec.edu.uce.yawar.inventory;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * ms-inventory: blood stock per center. It doubles as a CONTROLLABLE DOWNSTREAM for the
 * resilience demos (circuit breaker, retry, timeout): its failure mode can be changed at runtime.
 */
@SpringBootApplication
public class InventoryApplication {
    public static void main(String[] args) {
        SpringApplication.run(InventoryApplication.class, args);
    }
}
