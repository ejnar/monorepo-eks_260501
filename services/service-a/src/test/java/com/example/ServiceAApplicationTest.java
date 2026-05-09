package com.example;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;

@SpringBootTest
@TestPropertySource(properties = {
    "aws.secrets.enabled=false",
    "aws.region=us-east-1"
})
class ServiceAApplicationTest {

    @Test
    void contextLoads() {
    }
}
