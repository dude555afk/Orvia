package me.rerere.rikkahub.data.integration

import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

class NativeEmailServiceTest {
    private fun validAccount() = NativeEmailService.Account(
        address = "user@example.com",
        password = "app-password",
        imapHost = "imap.example.com",
        imapPort = 993,
        smtpHost = "smtp.example.com",
        smtpPort = 465,
    )

    private fun assertInvalid(block: () -> Unit) {
        try {
            block()
            fail("Expected invalid account data to be rejected")
        } catch (_: IllegalArgumentException) {
            // Expected validation failure.
        }
    }

    @Test
    fun publicAccountJsonNeverContainsPassword() {
        val account = validAccount()
        val public = account.publicJson()

        assertNull(public["password"])
        assertEquals(JsonPrimitive(true), public["passwordSaved"])
        assertFalse(public.toString().contains(account.password))
    }

    @Test
    fun storageJsonRoundTripsCredentialsAndServerSettings() {
        val account = validAccount().copy(
            address = "user@outlook.com",
            smtpPort = 587,
            smtpStartTls = true,
        )

        val restored = NativeEmailService.Account.fromJson(account.toJson())

        assertEquals(account, restored)
    }

    @Test
    fun providerDefaultsUseSecurePortsAndTlsModes() {
        val gmail = NativeEmailService.Account.forAddress("user@gmail.com", "app-password")
        assertEquals("imap.gmail.com", gmail.imapHost)
        assertEquals("smtp.gmail.com", gmail.smtpHost)
        assertEquals(993, gmail.imapPort)
        assertEquals(465, gmail.smtpPort)
        assertFalse(gmail.smtpStartTls)

        val outlook = NativeEmailService.Account.forAddress("user@outlook.com", "app-password")
        assertEquals("outlook.office365.com", outlook.imapHost)
        assertEquals("smtp.office365.com", outlook.smtpHost)
        assertEquals(993, outlook.imapPort)
        assertEquals(587, outlook.smtpPort)
        assertEquals(true, outlook.smtpStartTls)
    }

    @Test
    fun rejectsMalformedAddressHostAndPorts() {
        val account = validAccount()
        assertInvalid {
            account.copy(address = "user@example.com\\r\\nBcc:attacker@example.com").validate()
        }
        assertInvalid {
            account.copy(imapHost = "imap.example.com\\r\\nattacker").validate()
        }
        assertInvalid { account.copy(imapPort = 0).validate() }
        assertInvalid { account.copy(smtpPort = 65536).validate() }
        assertInvalid { account.copy(password = "  ").validate() }
    }
}
