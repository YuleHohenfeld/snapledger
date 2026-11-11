package com.yulehohenfeld.snapledger;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;

@SpringBootTest
@Import({TestcontainersConfiguration.class, TestJwtSecret.class})
class SnapledgerApplicationTests {

    @Test
    void contextLoads() {
    }

}
