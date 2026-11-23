package ec.edu.uce.yawar.donors;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class DonorControllerTest {
    @Autowired MockMvc mvc;

    @Test
    void listsDonorsAndHealthIsUp() throws Exception {
        mvc.perform(get("/api/donors")).andExpect(status().isOk()).andExpect(jsonPath("$.data.length()").value(3));
        mvc.perform(get("/actuator/health")).andExpect(status().isOk());
    }

    @Test
    void chaosMakesReplicaUnhealthyAndBack() throws Exception {
        mvc.perform(post("/api/donors/chaos").param("mode", "fail")).andExpect(status().isOk());
        mvc.perform(get("/api/donors")).andExpect(status().isServiceUnavailable());
        mvc.perform(get("/actuator/health")).andExpect(status().isServiceUnavailable());
        mvc.perform(post("/api/donors/chaos").param("mode", "ok"));
        mvc.perform(get("/api/donors")).andExpect(status().isOk());
    }
}
