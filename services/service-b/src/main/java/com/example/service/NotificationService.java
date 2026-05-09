package com.example.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.example.config.SecretsManagerConfig;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@Service
public class NotificationService {

    private static final Logger log = LoggerFactory.getLogger(NotificationService.class);

    private final SecretsManagerConfig secretsManagerConfig;

    public NotificationService(SecretsManagerConfig secretsManagerConfig) {
        this.secretsManagerConfig = secretsManagerConfig;
    }

    public Mono<Map<String, Object>> send(Map<String, Object> payload) {
        String notificationId = UUID.randomUUID().toString();
        log.info("Sending notification id={}", notificationId);

        Map<String, Object> result = new HashMap<>(payload);
        result.put("notificationId", notificationId);
        result.put("service", "service-b");
        result.put("timestamp", Instant.now().toString());
        result.put("status", "SENT");
        result.put("apiKey_hint", secretsManagerConfig.getSecretValue("notification-api-key"));

        return Mono.just(result);
    }

    public Flux<Map<String, Object>> streamNotifications() {
        return Flux.interval(Duration.ofSeconds(2))
                .map(tick -> {
                    Map<String, Object> data = new HashMap<>();
                    data.put("tick", tick);
                    data.put("service", "service-b");
                    data.put("message", "Heartbeat notification #" + tick);
                    data.put("timestamp", Instant.now().toString());
                    return data;
                })
                .take(10);
    }

}

/* 
    public Flux<Map<String, Object>> streamNotifications() {
        return Flux.interval(Duration.ofSeconds(2))
                .map(tick -> Map.of(
                        "tick", tick,
                        "service", "service-b",
                        "message", "Heartbeat notification #" + tick,
                        "timestamp", Instant.now().toString()
                ))
                .take(10);
    }
}
    */
