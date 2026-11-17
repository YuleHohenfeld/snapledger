package com.yulehohenfeld.snapledger.accountcode.entity;

/** What a code unlocks; part of the hashed input, so a code works for one purpose only.
 *  PT: O que o código libera; entra no hash, então um código vale para uma finalidade só.
 *  Notes: docs/code-notes/account-code.md#purpose-binding */
public enum CodePurpose {
    EMAIL_VERIFICATION,
    PASSWORD_RESET
}
