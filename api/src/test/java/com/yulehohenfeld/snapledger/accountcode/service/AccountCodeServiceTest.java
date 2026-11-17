package com.yulehohenfeld.snapledger.accountcode.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.mockito.ArgumentCaptor;

import com.yulehohenfeld.snapledger.accountcode.config.AccountCodeProperties;
import com.yulehohenfeld.snapledger.accountcode.entity.AccountCode;
import com.yulehohenfeld.snapledger.accountcode.entity.CodePurpose;
import com.yulehohenfeld.snapledger.accountcode.repository.AccountCodeRepository;
import com.yulehohenfeld.snapledger.support.AccountCodeFixtures;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;

/**
 * Issue and consume rules with a fixed clock and a mocked repository: format, replacement, limits,
 * and what a wrong or late guess does.
 *
 * <p>PT: Regras de emitir e consumir com relógio parado e repositório simulado: formato, troca,
 * limites, e o que um palpite errado ou tardio faz.
 */
@ExtendWith(OutputCaptureExtension.class)
class AccountCodeServiceTest {

    static final Instant NOW = Instant.parse("2026-11-17T12:00:00Z");
    static final Duration TTL = Duration.ofMinutes(15);

    final AccountCodeRepository codes = mock(AccountCodeRepository.class);
    final AccountCodeProperties properties = new AccountCodeProperties(TestJwtSecret.generate(), TTL, 5,
            Duration.ofSeconds(60), 5, 10, Duration.ofHours(24));
    final AccountCodeHasher hasher = new AccountCodeHasher(properties);
    final UUID userId = UUID.randomUUID();
    Instant now = NOW;
    AccountCodeService service;
    Clock clock;

    @BeforeEach
    void setUp() {
        // The clock reads the field on each call, so a test can move time forward.
        // PT: O relógio lê o campo a cada chamada, então um teste pode avançar o tempo.
        clock = new Clock() {
            @Override
            public java.time.ZoneId getZone() {
                return ZoneOffset.UTC;
            }

            @Override
            public Clock withZone(java.time.ZoneId zone) {
                return this;
            }

            @Override
            public Instant instant() {
                return now;
            }
        };
        service = new AccountCodeService(codes, hasher, properties, clock);
    }

    @Test
    void firstIssueInsertsAHashedSixDigitCodeAndReturnsIt() {
        when(codes.lock(userId, CodePurpose.EMAIL_VERIFICATION)).thenReturn(Optional.empty());
        when(codes.insertIfAbsent(any(), eq(userId), eq("EMAIL_VERIFICATION"), anyString(), eq(NOW),
                eq(NOW.plus(TTL)))).thenReturn(1);

        var code = service.issue(userId, CodePurpose.EMAIL_VERIFICATION).orElseThrow();

        assertThat(code).matches("^\\d{6}$");
        var hash = ArgumentCaptor.forClass(String.class);
        verify(codes).insertIfAbsent(any(), eq(userId), eq("EMAIL_VERIFICATION"), hash.capture(), eq(NOW),
                eq(NOW.plus(TTL)));
        assertThat(hash.getValue()).isEqualTo(hasher.hash(CodePurpose.EMAIL_VERIFICATION, userId, code));
    }

    @Test
    void codesAreZeroPaddedToSixDigits() {
        when(codes.lock(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.empty());
        when(codes.insertIfAbsent(any(), any(), anyString(), anyString(), any(), any())).thenReturn(1);

        for (int i = 0; i < 300; i++) {
            assertThat(service.issue(userId, CodePurpose.PASSWORD_RESET).orElseThrow()).hasSize(6).containsOnlyDigits();
        }
    }

    @Test
    void aConcurrentFirstInsertIsTreatedAsThrottled() {
        when(codes.lock(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.empty());
        when(codes.insertIfAbsent(any(), any(), anyString(), anyString(), any(), any())).thenReturn(0);

        assertThat(service.issue(userId, CodePurpose.PASSWORD_RESET)).isEmpty();
    }

    @Test
    void issueReplacesTheLiveCodeAndResetsAttempts() {
        var row = existingRow(CodePurpose.PASSWORD_RESET, "123456");
        row.recordFailedAttempt(NOW, Duration.ofHours(24));
        now = NOW.plusSeconds(61);
        when(codes.lock(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.of(row));

        var code = service.issue(userId, CodePurpose.PASSWORD_RESET).orElseThrow();

        assertThat(row.getAttempts()).isZero();
        assertThat(row.getUsedAt()).isNull();
        assertThat(row.getSentAt()).isEqualTo(now);
        assertThat(row.getExpiresAt()).isEqualTo(now.plus(TTL));
        assertThat(row.getSendsInWindow()).isEqualTo(2);
        assertThat(hasher.matches(CodePurpose.PASSWORD_RESET, userId, code, row.getCodeHash())).isTrue();
        verify(codes, never()).insertIfAbsent(any(), any(), anyString(), anyString(), any(), any());
    }

    @Test
    void issueInsideTheCooldownReturnsEmptyAndChangesNothing() {
        var row = existingRow(CodePurpose.PASSWORD_RESET, "123456");
        var hashBefore = row.getCodeHash();
        now = NOW.plusSeconds(59);
        when(codes.lock(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.of(row));

        assertThat(service.issue(userId, CodePurpose.PASSWORD_RESET)).isEmpty();
        assertThat(row.getCodeHash()).isEqualTo(hashBefore);
    }

    @Test
    void issueAfterTheHourlyQuotaReturnsEmptyUntilTheWindowEnds() {
        var row = existingRow(CodePurpose.PASSWORD_RESET, "123456");
        when(codes.lock(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.of(row));
        for (int i = 2; i <= 5; i++) {
            now = now.plusSeconds(61);
            assertThat(service.issue(userId, CodePurpose.PASSWORD_RESET)).isPresent();
        }
        assertThat(row.getSendsInWindow()).isEqualTo(5);

        now = now.plusSeconds(61);
        assertThat(service.issue(userId, CodePurpose.PASSWORD_RESET)).isEmpty();

        now = NOW.plus(AccountCode.RESEND_WINDOW);
        assertThat(service.issue(userId, CodePurpose.PASSWORD_RESET)).isPresent();
        assertThat(row.getSendsInWindow()).isEqualTo(1);
    }

    @Test
    void consumeAcceptsTheRightCodeOnceOnly() {
        var row = existingRow(CodePurpose.EMAIL_VERIFICATION, "654321");
        when(codes.lock(userId, CodePurpose.EMAIL_VERIFICATION)).thenReturn(Optional.of(row));

        assertThat(service.consume(userId, CodePurpose.EMAIL_VERIFICATION, "654321")).isTrue();
        assertThat(row.getUsedAt()).isEqualTo(NOW);
        assertThat(service.consume(userId, CodePurpose.EMAIL_VERIFICATION, "654321")).isFalse();
    }

    @Test
    void aWrongCodeCountsAnAttemptAndReturnsFalse() {
        var row = existingRow(CodePurpose.EMAIL_VERIFICATION, "654321");
        when(codes.lock(userId, CodePurpose.EMAIL_VERIFICATION)).thenReturn(Optional.of(row));

        assertThat(service.consume(userId, CodePurpose.EMAIL_VERIFICATION, "000000")).isFalse();
        assertThat(service.consume(userId, CodePurpose.EMAIL_VERIFICATION, null)).isFalse();

        assertThat(row.getAttempts()).isEqualTo(2);
        assertThat(row.getUsedAt()).isNull();
    }

    @Test
    void theSixthAttemptFailsEvenWithTheRightCode() {
        var row = existingRow(CodePurpose.EMAIL_VERIFICATION, "654321");
        when(codes.lock(userId, CodePurpose.EMAIL_VERIFICATION)).thenReturn(Optional.of(row));
        for (int i = 0; i < 5; i++) {
            assertThat(service.consume(userId, CodePurpose.EMAIL_VERIFICATION, "000000")).isFalse();
        }

        assertThat(service.consume(userId, CodePurpose.EMAIL_VERIFICATION, "654321")).isFalse();
        assertThat(row.getAttempts()).isEqualTo(5);
        assertThat(row.getUsedAt()).isNull();
    }

    @Test
    void anExpiredCodeFailsEvenWhenRight() {
        var row = existingRow(CodePurpose.EMAIL_VERIFICATION, "654321");
        now = NOW.plus(TTL);
        when(codes.lock(userId, CodePurpose.EMAIL_VERIFICATION)).thenReturn(Optional.of(row));

        assertThat(service.consume(userId, CodePurpose.EMAIL_VERIFICATION, "654321")).isFalse();
    }

    @Test
    void aCodeOfAnotherPurposeHasNoRowAndFails() {
        when(codes.lock(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.empty());

        assertThat(service.consume(userId, CodePurpose.PASSWORD_RESET, "654321")).isFalse();
    }

    @Test
    void aCodeIssuedForAnotherPurposeOrUserDoesNotMatchTheHash() {
        var row = existingRow(CodePurpose.EMAIL_VERIFICATION, "654321");
        // Same row served for a lookup of the wrong purpose/user: the HMAC input differs, so it fails.
        // PT: A mesma linha servida para a busca de outra finalidade/usuário: a entrada do HMAC difere, então falha.
        var otherUser = UUID.randomUUID();
        when(codes.lock(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.of(row));
        when(codes.lock(otherUser, CodePurpose.EMAIL_VERIFICATION)).thenReturn(Optional.of(row));

        assertThat(service.consume(userId, CodePurpose.PASSWORD_RESET, "654321")).isFalse();
        assertThat(service.consume(otherUser, CodePurpose.EMAIL_VERIFICATION, "654321")).isFalse();
    }

    @Test
    void reissueDoesNotResetTheFailureBudget() {
        var row = existingRow(CodePurpose.PASSWORD_RESET, "123456");
        when(codes.lock(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.of(row));
        for (int i = 0; i < 4; i++) {
            service.consume(userId, CodePurpose.PASSWORD_RESET, "000000");
        }
        now = NOW.plusSeconds(61);

        var code = service.issue(userId, CodePurpose.PASSWORD_RESET).orElseThrow();

        assertThat(row.getAttempts()).isZero();
        assertThat(row.getFailedInWindow()).isEqualTo(4);
        service.consume(userId, CodePurpose.PASSWORD_RESET, "000000");
        assertThat(row.getFailedInWindow()).isEqualTo(5);
        assertThat(service.consume(userId, CodePurpose.PASSWORD_RESET, code)).isTrue();
    }

    @Test
    void tenFailuresAcrossSeveralCodesBlockIssueAndConsumeEvenWithTheRightCode() {
        var row = existingRow(CodePurpose.PASSWORD_RESET, "123456");
        when(codes.lock(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.of(row));
        String code = null;
        for (int round = 0; round < 2; round++) {
            for (int i = 0; i < 5; i++) {
                service.consume(userId, CodePurpose.PASSWORD_RESET, "000000");
            }
            now = now.plusSeconds(61);
            if (round == 0) {
                code = service.issue(userId, CodePurpose.PASSWORD_RESET).orElseThrow();
            }
        }

        assertThat(row.getFailedInWindow()).isEqualTo(10);
        assertThat(service.issue(userId, CodePurpose.PASSWORD_RESET)).isEmpty();
        assertThat(service.consume(userId, CodePurpose.PASSWORD_RESET, code)).isFalse();
        assertThat(row.getUsedAt()).isNull();
    }

    @Test
    void theFailureBudgetComesBackAfter24HoursAndASuccessResetsIt() {
        var row = existingRow(CodePurpose.PASSWORD_RESET, "123456");
        when(codes.lock(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.of(row));
        for (int i = 0; i < 10; i++) {
            row.recordFailedAttempt(NOW, Duration.ofHours(24));
        }
        now = NOW.plus(Duration.ofHours(24)).minusSeconds(1);
        assertThat(service.issue(userId, CodePurpose.PASSWORD_RESET)).isEmpty();

        now = NOW.plus(Duration.ofHours(24));
        var code = service.issue(userId, CodePurpose.PASSWORD_RESET).orElseThrow();
        service.consume(userId, CodePurpose.PASSWORD_RESET, "000000");
        assertThat(row.getFailedInWindow()).isEqualTo(1);

        assertThat(service.consume(userId, CodePurpose.PASSWORD_RESET, code)).isTrue();
        assertThat(row.getFailedInWindow()).isZero();
        assertThat(row.getFailedWindowStartedAt()).isNull();
    }

    // Security event: exactly one WARN when the budget is spent, with ids only (api/CLAUDE.md rule 8).
    // PT: Evento de segurança: exatamente um WARN quando o orçamento esgota, só com ids (regra 8 do api/CLAUDE.md).
    @Test
    void spendingTheFailureBudgetLogsOneWarnWithUserIdAndPurposeOnly(CapturedOutput output) {
        var row = existingRow(CodePurpose.PASSWORD_RESET, "123456");
        when(codes.lock(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.of(row));

        for (int round = 0; round < 3; round++) {
            for (int i = 0; i < 5; i++) {
                service.consume(userId, CodePurpose.PASSWORD_RESET, "987654");
            }
            now = now.plusSeconds(61);
            service.issue(userId, CodePurpose.PASSWORD_RESET);
        }

        var line = "Account code failure budget exhausted userId=" + userId + " purpose=PASSWORD_RESET";
        assertThat(output.getAll().split(line, -1)).hasSize(2);
        assertThat(output.getAll()).doesNotContain("987654");
    }

    @Test
    void aGuessThatDoesNotSpendTheBudgetLogsNothing(CapturedOutput output) {
        var row = existingRow(CodePurpose.PASSWORD_RESET, "123456");
        when(codes.lock(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.of(row));

        service.consume(userId, CodePurpose.PASSWORD_RESET, "000000");

        assertThat(output.getAll()).doesNotContain("budget exhausted");
    }

    @Test
    void theResendCooldownIsTheConfiguredOne() {
        assertThat(service.resendCooldown()).isEqualTo(Duration.ofSeconds(60));
    }

    @Test
    void aThrottledIssueDoesNotComputeAHash() {
        var row = existingRow(CodePurpose.PASSWORD_RESET, "123456");
        now = NOW.plusSeconds(10);
        when(codes.lock(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.of(row));
        var spy = org.mockito.Mockito.spy(hasher);
        var guarded = new AccountCodeService(codes, spy, properties, clock);

        assertThat(guarded.issue(userId, CodePurpose.PASSWORD_RESET)).isEmpty();
        verify(spy, never()).hash(any(), any(), anyString());
    }

    // A row as the first issue would leave it, with a known code.
    // PT: Uma linha como a primeira emissão a deixaria, com um código conhecido.
    private AccountCode existingRow(CodePurpose purpose, String code) {
        return AccountCodeFixtures.row(userId, purpose, hasher.hash(purpose, userId, code), NOW, TTL);
    }
}
