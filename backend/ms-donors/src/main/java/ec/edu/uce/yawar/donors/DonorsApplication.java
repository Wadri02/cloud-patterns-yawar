package ec.edu.uce.yawar.donors;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** ms-donors: Yawar donor registry. Runs as several replicas behind the ALB (load-balancing demo). */
@SpringBootApplication
public class DonorsApplication {
    public static void main(String[] args) {
        SpringApplication.run(DonorsApplication.class, args);
    }
}
