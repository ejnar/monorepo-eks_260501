package com.example.service;

import com.example.config.SecretsManagerConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;


@Service
public class ItemService {

    private static final Logger log = LoggerFactory.getLogger(ItemService.class);

    private final SecretsManagerConfig secretsManagerConfig;
    private final AtomicLong idCounter = new AtomicLong(1);
    private final List<Map<String, Object>> store = new ArrayList<>();

    public ItemService(SecretsManagerConfig secretsManagerConfig) {
        this.secretsManagerConfig = secretsManagerConfig;
    }

    public List<Map<String, Object>> getAllItems() {
        log.info("Fetching all items from service-a");
        return store;
    }

    public Map<String, Object> getItem(Long id) {
        return store.stream()
                .filter(item -> id.equals(item.get("id")))
                .findFirst()
                .orElseThrow(() -> new RuntimeException("Item not found: " + id));
    }

    public Map<String, Object> createItem(Map<String, Object> payload) {
        Map<String, Object> item = new HashMap<>(payload);
        item.put("id", idCounter.getAndIncrement());
        item.put("service", "service-a");
        item.put("secret_hint", secretsManagerConfig.getSecretValue("app-secret-key"));
        store.add(item);
        log.info("Created item with id={}", item.get("id"));
        return item;
    }
}
