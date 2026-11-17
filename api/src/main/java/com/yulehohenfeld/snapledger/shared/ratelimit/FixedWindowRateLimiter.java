package com.yulehohenfeld.snapledger.shared.ratelimit;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

import org.springframework.stereotype.Component;

/**
 * In-memory fixed-window counter per (bucket, key). The number of tracked keys is capped, and when
 * the cap is reached with no expired window to purge, a new key is refused (fail closed).
 *
 * <p>PT: Contador de janela fixa em memória por (bucket, chave). O número de chaves rastreadas tem
 * teto, e quando o teto é atingido sem nenhuma janela vencida para limpar, uma chave nova é
 * recusada (falha fechada).
 * Notes: docs/code-notes/security.md#rate-limiting
 */
@Component
public class FixedWindowRateLimiter {

    /** {@code retryAfter} is how long until the window of the refused key ends. PT: Quanto falta para a janela da chave recusada terminar. */
    public record Decision(boolean allowed, Duration retryAfter) {
    }

    private record Window(Instant start, int count) {
    }

    private final Clock clock;
    private final RateLimitProperties properties;

    // Plain map under one lock: the cap check, the purge and the increment must be one atomic step.
    // PT: Mapa simples sob um lock só: a checagem do teto, a limpeza e o incremento são um passo atômico.
    private final Map<String, Window> windows = new HashMap<>();

    public FixedWindowRateLimiter(Clock clock, RateLimitProperties properties) {
        this.clock = clock;
        this.properties = properties;
    }

    public synchronized Decision tryAcquire(String bucket, String key) {
        var now = clock.instant();
        var limit = properties.limitOf(bucket);
        var window = properties.window();
        var id = bucket + '|' + key;
        var current = windows.get(id);

        if (current == null || !now.isBefore(current.start().plus(window))) {
            if (current == null && windows.size() >= properties.maxTrackedKeys()) {
                purgeExpired(now, window);
                if (windows.size() >= properties.maxTrackedKeys()) {
                    return new Decision(false, window);
                }
            }
            windows.put(id, new Window(now, 1));
            return new Decision(true, Duration.ZERO);
        }
        if (current.count() >= limit) {
            return new Decision(false, Duration.between(now, current.start().plus(window)));
        }
        windows.put(id, new Window(current.start(), current.count() + 1));
        return new Decision(true, Duration.ZERO);
    }

    private void purgeExpired(Instant now, Duration window) {
        windows.values().removeIf(w -> !now.isBefore(w.start().plus(window)));
    }
}
