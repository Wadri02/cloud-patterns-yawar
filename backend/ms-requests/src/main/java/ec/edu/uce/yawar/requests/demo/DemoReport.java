package ec.edu.uce.yawar.requests.demo;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.logging.Logger;

/** Collects the lines of a demo run; each line is also logged (-> CloudWatch Logs in AWS). */
public class DemoReport {
    private static final Logger LOG = Logger.getLogger("demo");
    private final String demo;
    private final String impl;
    private final List<String> log = new ArrayList<>();
    private final Map<String, Object> summary = new LinkedHashMap<>();

    public DemoReport(String demo, String impl) {
        this.demo = demo;
        this.impl = impl;
        line("=== " + Instant.now() + " " + demo + " demo (impl=" + impl + ") ===");
    }

    public void line(String s) {
        log.add(s);
        LOG.info("[" + demo + "/" + impl + "] " + s);
    }

    public void put(String key, Object value) { summary.put(key, value); }

    public Map<String, Object> toMap() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("demo", demo);
        m.put("impl", impl);
        m.put("summary", summary);
        m.put("log", log);
        return m;
    }
}
