package com.example.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueResponse;

@Configuration
public class SecretsManagerConfig {

    private static final Logger log = LoggerFactory.getLogger(SecretsManagerConfig.class);

    @Value("${aws.region:us-east-1}")
    private String awsRegion;

    @Value("${aws.secrets.enabled:false}")
    private boolean secretsEnabled;

    public String getSecretValue(String secretName) {
        if (!secretsEnabled) {
            log.warn("AWS Secrets Manager disabled; returning placeholder for '{}'", secretName);
            return "local-placeholder";
        }
        try (SecretsManagerClient client = SecretsManagerClient.builder()
                .region(Region.of(awsRegion))
                .build()) {
            GetSecretValueRequest request = GetSecretValueRequest.builder()
                    .secretId(secretName)
                    .build();
            GetSecretValueResponse response = client.getSecretValue(request);
            return response.secretString();
        } catch (Exception e) {
            log.error("Failed to retrieve secret '{}': {}", secretName, e.getMessage());
            return "error-retrieving-secret";
        }
    }
}
