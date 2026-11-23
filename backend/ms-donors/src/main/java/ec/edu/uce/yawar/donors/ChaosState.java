package ec.edu.uce.yawar.donors;

import java.util.concurrent.atomic.AtomicBoolean;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.stereotype.Component;

/**
 * Failure injection. When "failing" is true the replica answers 503 and /actuator/health reports DOWN,
 * so the ALB target group marks it unhealthy and ECS replaces the task (self-healing demo).
 */
@Component
public class ChaosState implements HealthIndicator {
    private final AtomicBoolean failing = new AtomicBoolean(false);

    public boolean isFailing() { return failing.get(); }

    public void setFailing(boolean value) { failing.set(value); }

    @Override
    public Health health() {
        return failing.get() ? Health.down().withDetail("chaos", "fail").build() : Health.up().build();
    }
}
