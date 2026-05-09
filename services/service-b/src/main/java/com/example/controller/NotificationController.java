package com.example.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.example.service.NotificationService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.Map;

@RestController
@RequestMapping("/api/v1/notifications")
public class NotificationController {

    private static final Logger log = LoggerFactory.getLogger(NotificationController.class);

    private final NotificationService notificationService;

    public NotificationController(NotificationService notificationService) {
        this.notificationService = notificationService;
    }

    @PostMapping("/send")
    public Mono<ResponseEntity<Map<String, Object>>> sendNotification(
            @RequestBody Map<String, Object> payload) {
        return notificationService.send(payload)
                .map(ResponseEntity::ok);
    }

    @GetMapping("/stream")
    public Flux<Map<String, Object>> streamNotifications() {
        return notificationService.streamNotifications();
    }

    @GetMapping("/health")
    public Mono<ResponseEntity<Map<String, String>>> health() {
        return Mono.just(ResponseEntity.ok(
                Map.of("service", "service-b", "status", "UP")));
    }
}
