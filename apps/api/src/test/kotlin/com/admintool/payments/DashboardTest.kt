package com.admintool.payments

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get

@SpringBootTest
@AutoConfigureMockMvc
class DashboardTest {
    @Autowired lateinit var mvc: MockMvc
    @Autowired lateinit var service: DashboardService

    @Test
    fun `aggregates exact cents and reconciles accounts for every month`() {
        val result = service.dashboard(2026)
        assertThat(result.months.map { it.month }).containsExactlyElementsOf(1..12)
        val source = service.payments(2026)
        result.months.forEach { month ->
            assertThat(month.accounts).hasSize(3)
            val payments = source.filter { it.date.monthValue == month.month }
            assertThat(month.totals.incomingCents).isEqualTo(payments.filter { it.direction == Direction.INCOMING }.sumOf { it.amountCents })
            assertThat(month.totals.outgoingCents).isEqualTo(payments.filter { it.direction == Direction.OUTGOING }.sumOf { it.amountCents })
            assertThat(month.totals.netCents).isEqualTo(month.totals.incomingCents - month.totals.outgoingCents)
            assertThat(month.accounts.sumOf { it.totals.incomingCents }).isEqualTo(month.totals.incomingCents)
            assertThat(month.accounts.sumOf { it.totals.outgoingCents }).isEqualTo(month.totals.outgoingCents)
            month.accounts.forEach { summary ->
                val own = payments.filter { it.accountId == summary.account.id }
                assertThat(summary.totals.incomingCents).isEqualTo(own.filter { it.direction == Direction.INCOMING }.sumOf { it.amountCents })
                assertThat(summary.totals.outgoingCents).isEqualTo(own.filter { it.direction == Direction.OUTGOING }.sumOf { it.amountCents })
            }
        }
        assertThat(result.months.first().totals).isEqualTo(Totals(6_208_725, 4_105_575))
    }

    @Test
    fun `serves the mock dashboard contract for the requested year`() {
        mvc.get("/api/dashboard?year=2025").andExpect {
            status { isOk() }
            jsonPath("$.year") { value(2025) }
            jsonPath("$.currency") { value("USD") }
            jsonPath("$.mockData") { value(true) }
            jsonPath("$.months.length()") { value(12) }
            jsonPath("$.months[0].accounts.length()") { value(3) }
            jsonPath("$.months[0].totals.netCents") { value(2_103_150) }
        }
        assertThat(service.payments(2025).map { it.date.year }.toSet()).containsExactly(2025)
    }

    @Test
    fun `rejects invalid years and supplies a usable default`() {
        listOf("1999", "2101", "nonsense").forEach { year ->
            mvc.get("/api/dashboard?year=$year").andExpect { status { isBadRequest() } }
        }
        mvc.get("/api/dashboard").andExpect { status { isOk() }; jsonPath("$.year") { value(2026) } }
    }
}
