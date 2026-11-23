package ec.edu.uce.yawar.inventory;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class InventoryControllerTest {
    @Autowired MockMvc mvc;

    @BeforeEach
    void reset() throws Exception {
        mvc.perform(post("/api/inventory/admin/reset"));
    }

    @Test
    void flakyModeFailsNTimesThenRecovers() throws Exception {
        mvc.perform(post("/api/inventory/admin/mode").param("mode", "flaky:2"));
        mvc.perform(get("/api/inventory")).andExpect(status().isServiceUnavailable());
        mvc.perform(get("/api/inventory")).andExpect(status().isServiceUnavailable());
        mvc.perform(get("/api/inventory")).andExpect(status().isOk());
    }

    @Test
    void idempotencyKeyPreventsDuplicates() throws Exception {
        mvc.perform(post("/api/inventory/admin/mode").param("mode", "lost:1"));
        String body = "{\"donor\":\"D-001\",\"bloodType\":\"O+\"}";
        mvc.perform(post("/api/inventory/donations").header("Idempotency-Key", "k1")
                .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isServiceUnavailable());
        mvc.perform(post("/api/inventory/donations").header("Idempotency-Key", "k1")
                .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk()).andExpect(jsonPath("$.replayed").value(true));
        mvc.perform(get("/api/inventory/admin/stats")).andExpect(jsonPath("$.donationsStored").value(1));
    }

    @Test
    void refusesWorkWhenDeadlineTooShort() throws Exception {
        mvc.perform(get("/api/inventory/report").param("workMs", "800").header("X-Deadline-Ms", "300"))
                .andExpect(status().isGatewayTimeout());
    }
}
