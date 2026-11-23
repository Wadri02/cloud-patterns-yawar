package ec.edu.uce.yawar.requests;

import ec.edu.uce.yawar.requests.client.InventoryClient;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

/**
 * ms-requests: hospitals' blood requests. It depends on ms-inventory, so it is where Yawar applies
 * the resilience patterns (circuit breaker, retry, timeout) - both our own implementation and Resilience4j.
 */
@SpringBootApplication
public class RequestsApplication {
    public static void main(String[] args) {
        SpringApplication.run(RequestsApplication.class, args);
    }

    @Bean
    InventoryClient inventoryClient(@Value("${yawar.inventory-url}") String url) {
        return new InventoryClient(url, Duration.ofMillis(500));
    }
}
