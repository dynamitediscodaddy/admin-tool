"use client";

import { useEffect, useState } from "react";

type Totals = {
  incomingCents: number;
  outgoingCents: number;
  netCents: number;
};
type Month = {
  month: number;
  totals: Totals;
  accounts: {
    account: { id: string; name: string; bank: string; lastFour: string };
    totals: Totals;
  }[];
};
type Dashboard = {
  year: number;
  currency: string;
  mockData: boolean;
  months: Month[];
};
const months = Array.from({ length: 12 }, (_, i) =>
  new Date(2026, i).toLocaleString("en-US", { month: "long" }),
);
const money = (cents: number) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(
    cents / 100,
  );

export default function Page() {
  const [year, setYear] = useState(2026);
  const [month, setMonth] = useState(10);
  const [data, setData] = useState<Dashboard | null>(null);
  const [error, setError] = useState(false);
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    setData(null);
    setError(false);
    fetch(`/api/dashboard?year=${year}`, { signal: controller.signal })
      .then((response) => {
        if (!response.ok) throw new Error("Request failed");
        return response.json() as Promise<Dashboard>;
      })
      .then(setData)
      .catch(() => {
        if (!controller.signal.aborted) setError(true);
      });
    return () => controller.abort();
  }, [year, attempt]);
  const selected = data?.months.find((item) => item.month === month);
  const peak = Math.max(
    1,
    ...(data?.months.flatMap((item) => [
      item.totals.incomingCents,
      item.totals.outgoingCents,
    ]) ?? []),
  );
  return (
    <div className="shell">
      <aside>
        <a className="brand" href="/">
          a<span>admin tool</span>
        </a>
        <div className="workspace">WORKSPACE</div>
        <a className="nav active" href="/">
          ▦ <span>Payments overview</span>
        </a>
        <div className="aside-bottom">
          <span className="avatar">AT</span>
          <div>
            Admin workspace<small>Finance team</small>
          </div>
        </div>
      </aside>
      <main>
        <header>
          <span>
            Workspace <b>/</b> Payments
          </span>
          <span className="pill">● Demo environment</span>
        </header>
        <section className="heading">
          <div>
            <p className="eyebrow">YOUR FINANCES, AT A GLANCE</p>
            <h1>Payments overview</h1>
            <p className="muted">
              A clear view of money moving across all your accounts.
            </p>
          </div>
          <div className="filters">
            <label>
              Month
              <select
                aria-label="Month"
                value={month}
                onChange={(e) => setMonth(Number(e.target.value))}
              >
                {months.map((name, i) => (
                  <option key={name} value={i + 1}>
                    {name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Year
              <select
                aria-label="Year"
                value={year}
                onChange={(e) => setYear(Number(e.target.value))}
              >
                {[2025, 2026, 2027].map((value) => (
                  <option key={value}>{value}</option>
                ))}
              </select>
            </label>
          </div>
        </section>
        <div aria-live="polite" aria-busy={!data && !error}>
          {error ? (
            <section className="panel notice" role="alert">
              <h2>Unable to load payments</h2>
              <p>Check that the payments API is running, then try again.</p>
              <button onClick={() => setAttempt((value) => value + 1)}>
                Try again
              </button>
            </section>
          ) : !selected ? (
            <section className="panel notice">
              Loading your payment overview…
            </section>
          ) : (
            <>
              <div className="period">
                <span>
                  {months[month - 1]} {year}
                </span>
                <span>All {selected.accounts.length} accounts · USD</span>
              </div>
              <section className="cards" aria-label="Monthly payment totals">
                <article className="card">
                  <span className="metric-icon incoming">↙</span>
                  <p>Total incoming</p>
                  <strong>{money(selected.totals.incomingCents)}</strong>
                  <small>Payments received this month</small>
                </article>
                <article className="card">
                  <span className="metric-icon outgoing">↗</span>
                  <p>Total outgoing</p>
                  <strong>{money(selected.totals.outgoingCents)}</strong>
                  <small>Payments sent this month</small>
                </article>
                <article className="card net">
                  <span className="metric-icon">⇄</span>
                  <p>Net cash flow</p>
                  <strong>{money(selected.totals.netCents)}</strong>
                  <small>Incoming minus outgoing</small>
                </article>
              </section>
              <section className="panel">
                <div className="panel-heading">
                  <div>
                    <h2>Cash flow</h2>
                    <p className="muted">
                      Monthly incoming and outgoing payments · {year}
                    </p>
                  </div>
                  <div className="legend">
                    <span>
                      <i className="in-dot" />
                      Incoming
                    </span>
                    <span>
                      <i className="out-dot" />
                      Outgoing
                    </span>
                  </div>
                </div>
                <div
                  className="chart"
                  aria-label="Monthly cash flow. Select a month to view its account breakdown."
                >
                  {data?.months.map((item) => (
                    <button
                      key={item.month}
                      className={`chart-column ${month === item.month ? "selected" : ""}`}
                      onClick={() => setMonth(item.month)}
                      aria-pressed={month === item.month}
                      aria-label={`${months[item.month - 1]}: incoming ${money(item.totals.incomingCents)}, outgoing ${money(item.totals.outgoingCents)}`}
                    >
                      <span className="bars">
                        <span
                          className="bar in-bar"
                          style={{
                            height: `${(item.totals.incomingCents / peak) * 100}%`,
                          }}
                        />
                        <span
                          className="bar out-bar"
                          style={{
                            height: `${(item.totals.outgoingCents / peak) * 100}%`,
                          }}
                        />
                      </span>
                      <span>{months[item.month - 1].slice(0, 3)}</span>
                    </button>
                  ))}
                </div>
                <p className="chart-note">
                  Select a month to explore its payments. Bar heights share a
                  zero baseline.
                </p>
              </section>
              <section className="panel accounts">
                <div className="panel-heading">
                  <div>
                    <h2>Account breakdown</h2>
                    <p className="muted">
                      Where your money moved in {months[month - 1]}.
                    </p>
                  </div>
                  <span className="count">
                    {selected.accounts.length} accounts
                  </span>
                </div>
                <div className="table-scroll">
                  <table>
                    <caption className="sr-only">
                      {months[month - 1]} {year} payment totals by bank account
                      in USD
                    </caption>
                    <thead>
                      <tr>
                        <th scope="col">Bank account</th>
                        <th scope="col">Incoming</th>
                        <th scope="col">Outgoing</th>
                        <th scope="col">Net cash flow</th>
                      </tr>
                    </thead>
                    <tbody>
                      {selected.accounts.map(({ account, totals }) => (
                        <tr key={account.id}>
                          <th scope="row">
                            <div className="account-name">
                              <span className={`bank ${account.id}`}>
                                {account.bank.slice(0, 1)}
                              </span>
                              <div>
                                {account.name}
                                <small>
                                  {account.bank} · •••• {account.lastFour}
                                </small>
                              </div>
                            </div>
                          </th>
                          <td className="positive">
                            {money(totals.incomingCents)}
                          </td>
                          <td>{money(totals.outgoingCents)}</td>
                          <td>{money(totals.netCents)}</td>
                        </tr>
                      ))}
                    </tbody>
                    <tfoot>
                      <tr>
                        <th scope="row">All accounts</th>
                        <td className="positive">
                          {money(selected.totals.incomingCents)}
                        </td>
                        <td>{money(selected.totals.outgoingCents)}</td>
                        <td>{money(selected.totals.netCents)}</td>
                      </tr>
                    </tfoot>
                  </table>
                </div>
              </section>
              {data?.mockData && (
                <footer>
                  <span className="demo-dot" /> Sample data for exploration. No
                  live bank connections.
                </footer>
              )}
            </>
          )}
        </div>
      </main>
    </div>
  );
}
