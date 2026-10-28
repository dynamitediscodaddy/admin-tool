package com.admintool.payments

import java.time.LocalDate
import org.springframework.stereotype.Service
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.server.ResponseStatusException
import org.springframework.http.HttpStatus

data class Account(val id: String, val name: String, val bank: String, val lastFour: String)
enum class Direction { INCOMING, OUTGOING }
data class Payment(val accountId: String, val date: LocalDate, val direction: Direction, val amountCents: Long)
data class Totals(val incomingCents: Long, val outgoingCents: Long) {
    val netCents: Long get() = incomingCents - outgoingCents
}
data class AccountSummary(val account: Account, val totals: Totals)
data class MonthSummary(val month: Int, val totals: Totals, val accounts: List<AccountSummary>)
data class Dashboard(val year: Int, val currency: String, val mockData: Boolean, val months: List<MonthSummary>)

@Service
class DashboardService {
    private val accounts = listOf(
        Account("operating", "Operating account", "Chase", "4821"),
        Account("reserve", "Business reserve", "Mercury", "9036"),
        Account("expenses", "Expenses account", "Bank of America", "1174")
    )

    // Deterministic external payments; internal transfers are deliberately excluded.
    // Integer minor units avoid floating-point rounding in monetary aggregation.
    fun payments(year: Int): List<Payment> = (1..12).flatMap { month ->
        accounts.flatMapIndexed { index, account ->
            listOf(
                Payment(account.id, LocalDate.of(year, month, 5), Direction.INCOMING, 1_250_000L + month * 84_500L + index * 235_000L),
                Payment(account.id, LocalDate.of(year, month, 18), Direction.INCOMING, 425_075L + index * 75_000L),
                Payment(account.id, LocalDate.of(year, month, 10), Direction.OUTGOING, 845_025L + month * 31_000L + index * 125_000L),
                Payment(account.id, LocalDate.of(year, month, 25), Direction.OUTGOING, 325_000L + index * 42_500L)
            )
        }
    }

    fun dashboard(year: Int): Dashboard {
        val payments = payments(year)
        return Dashboard(year, "USD", true, (1..12).map { month ->
            val monthly = payments.filter { it.date.monthValue == month }
            MonthSummary(month, total(monthly), accounts.map { account ->
                AccountSummary(account, total(monthly.filter { it.accountId == account.id }))
            })
        })
    }

    private fun total(payments: List<Payment>) = Totals(
        payments.filter { it.direction == Direction.INCOMING }.sumOf { it.amountCents },
        payments.filter { it.direction == Direction.OUTGOING }.sumOf { it.amountCents }
    )
}

@RestController
class DashboardController(private val service: DashboardService) {
    @GetMapping("/api/dashboard")
    fun dashboard(@RequestParam(defaultValue = "2026") year: Int): Dashboard {
        if (year !in 2000..2100) throw ResponseStatusException(HttpStatus.BAD_REQUEST, "Year must be between 2000 and 2100")
        return service.dashboard(year)
    }
}
