package com.yulehohenfeld.snapledger;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class SnapledgerApplication {

    public static void main(String[] args) {
        SpringApplication.run(SnapledgerApplication.class, args);
    }

}
