package ec.edu.uce.yawar.legacy;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.util.Properties;
import java.util.concurrent.Executors;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * "Yawar legacy donor registry" v1.4.2 - an old-style monolith that runs on an ON-PREMISES server.
 * No frameworks: JDK HTTP server, state in a local file, config in /etc/yawar/app.conf.
 * In the lift-and-shift (rehost) migration this exact JAR, its config and its data file are moved
 * to an EC2 instance without code changes. GET /about returns the SHA-256 of the running JAR so
 * we can prove the binary is identical on both sides.
 */
public class LegacyRegistry {
    static final String VERSION = "1.4.2";

    public static void main(String[] args) throws Exception {
        Path confFile = Path.of(System.getProperty("yawar.conf", "/etc/yawar/app.conf"));
        Properties conf = new Properties();
        if (Files.exists(confFile)) {
            try (InputStream in = Files.newInputStream(confFile)) { conf.load(in); }
        }
        Path data = Path.of(conf.getProperty("data_file", "/var/lib/yawar/donors.csv"));
        Files.createDirectories(data.getParent());
        if (!Files.exists(data)) { Files.writeString(data, ""); }
        int port = Integer.parseInt(conf.getProperty("port", "8080"));
        String host = InetAddress.getLocalHost().getHostName();
        String site = conf.getProperty("site", "unknown");
        String started = Instant.now().toString();
        String jarSha = selfSha256();

        HttpServer server = HttpServer.create(new InetSocketAddress(port), 50);
        server.setExecutor(Executors.newFixedThreadPool(8));
        server.createContext("/health", x -> reply(x, 200, "\"OK\""));
        server.createContext("/about", x -> reply(x, 200, String.format(
                "{\"app\":\"yawar-legacy-registry\",\"version\":\"%s\",\"host\":\"%s\",\"site\":\"%s\",\"started\":\"%s\",\"jarSha256\":\"%s\",\"java\":\"%s\"}",
                VERSION, host, site, started, jarSha, System.getProperty("java.version"))));
        server.createContext("/donors", x -> {
            synchronized (LegacyRegistry.class) {
                if ("POST".equals(x.getRequestMethod())) {
                    String body = new String(x.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
                    String id = field(body, "id"), name = field(body, "name"), type = field(body, "bloodType");
                    if (id == null || name == null || type == null) {
                        reply(x, 400, "{\"error\":\"id, name and bloodType are required\"}");
                        return;
                    }
                    Files.writeString(data, id + ";" + name + ";" + type + "\n", StandardCharsets.UTF_8,
                            java.nio.file.StandardOpenOption.APPEND);
                    reply(x, 201, list(data));
                    return;
                }
                reply(x, 200, list(data));
            }
        });
        server.start();
        System.out.printf("legacy registry v%s on %s site=%s data=%s jar=%s%n", VERSION, host, site, data, jarSha);
    }

    static String list(Path data) throws IOException {
        List<String> lines = Files.readAllLines(data, StandardCharsets.UTF_8);
        StringBuilder sb = new StringBuilder("[");
        for (String l : lines) {
            if (l.isBlank()) { continue; }
            String[] p = l.split(";");
            if (sb.length() > 1) { sb.append(','); }
            sb.append(String.format("{\"id\":\"%s\",\"name\":\"%s\",\"bloodType\":\"%s\"}", p[0], p[1], p[2]));
        }
        return sb.append(']').toString();
    }

    static String field(String json, String key) {
        Matcher m = Pattern.compile("\"" + key + "\"\\s*:\\s*\"([^\"]*)\"").matcher(json);
        return m.find() ? m.group(1) : null;
    }

    static String selfSha256() {
        try {
            Path jar = Path.of(LegacyRegistry.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            if (!Files.isRegularFile(jar)) { return "not-running-from-jar"; }
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(jar)));
        } catch (Exception e) {
            return "unknown";
        }
    }

    static void reply(HttpExchange x, int code, String json) throws IOException {
        byte[] b = json.getBytes(StandardCharsets.UTF_8);
        x.getResponseHeaders().set("Content-Type", "application/json");
        x.sendResponseHeaders(code, b.length);
        x.getResponseBody().write(b);
        x.close();
    }
}
