package ec.edu.uce.yawar.requests.resilience;

public class CircuitOpenException extends RuntimeException {
    public CircuitOpenException(String message) { super(message); }
}
