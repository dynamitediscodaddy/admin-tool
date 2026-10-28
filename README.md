# Admin tool

A monorepo with a Next.js 16 / React 19 TypeScript frontend and a Spring Boot 3.5 Kotlin API. The first feature is a monthly payments dashboard across three mock bank accounts.

## Run locally

Requires Node.js 24 and Java 21. The Maven wrapper downloads Maven on first use. No database, bank credentials, or environment variables are needed.

From the repository root:

```sh
npm ci
```

Start the API in one terminal:

```sh
cd apps/api
./mvnw spring-boot:run
```

In another terminal, from the repository root:

```sh
npm run dev
```

Open http://localhost:3000. The frontend proxies `/api/*` to http://localhost:8080. To change the backend address, copy `apps/web/.env.example` to `apps/web/.env.local`, edit `API_BASE_URL`, and restart Next.js.

For a production frontend build, run `npm run build` then `npm run start --workspace apps/web`. The API must also be running. `API_BASE_URL` is read at runtime, so the same frontend image can target different API hosts.

## Dashboard

- Select a month and year to see total incoming, outgoing, and net cash flow.
- Select a bar group in the yearly chart to change the month, including by keyboard.
- The account table shows the same monthly totals broken down by account, with a reconciled all-accounts footer.
- Loading, API failure, and retry states are provided. Mock data is visibly identified.

## API and data conventions

`GET /api/dashboard?year=2026` returns all twelve months, each with aggregate totals and account summaries. The year defaults to 2026; integers from 2000 through 2100 are accepted. Invalid years return HTTP 400.

```json
{
  "year": 2026,
  "currency": "USD",
  "mockData": true,
  "months": [
    {
      "month": 1,
      "totals": {
        "incomingCents": 6208725,
        "outgoingCents": 4105575,
        "netCents": 2103150
      },
      "accounts": [
        {
          "account": {
            "id": "operating",
            "name": "Operating account",
            "bank": "Chase",
            "lastFour": "4821"
          },
          "totals": {
            "incomingCents": 1759575,
            "outgoingCents": 1201025,
            "netCents": 558550
          }
        }
      ]
    }
  ]
}
```

The example abbreviates the months and accounts arrays. All amounts are integer USD cents; outgoing amounts are positive and net equals incoming minus outgoing. The backend aggregates individual deterministic mock payments by calendar month and account. All accounts use USD, and the fixtures represent external payments only, excluding internal transfers to avoid double counting. Fixtures intentionally repeat for each requested year and include all twelve months, including future months; these are demonstration values, not forecasts or live balances. Replace the fixture source in `DashboardService` when integrating real data.

## Checks

```sh
npm run typecheck
npm run build
cd apps/api
./mvnw verify
```

Backend tests cover exact monetary aggregation, per-account reconciliation, year selection, the HTTP response contract, and invalid inputs. GitHub Actions runs frontend checks and backend verification on pull requests and on pushes to main.

## Layout

- `apps/web`: Next.js App Router frontend and API proxy configuration.
- `apps/api`: Spring Boot application, mock payments, aggregation, and API tests.
- `.github/workflows/ci.yml`: frontend and backend checks.

This initial scaffold has no authentication or live bank integration. Add access control before exposing financial data in a deployed environment.

## Container deployment

Build and run both services with Docker Compose:

```sh
docker compose up --build -d
```

Open http://localhost:3000. Only the frontend is exposed; its `/api/dashboard` route forwards requests to the API over the container network. The backend image runs its tests during the build. Both runtime containers use non-root users.

On a container hosting provider, build from the repository root using `apps/api/Dockerfile` and `apps/web/Dockerfile`. Set the frontend's runtime `API_BASE_URL` to the backend's reachable HTTP(S) origin (including the scheme and port if needed). Default ports are 8080 for the API and 3000 for the frontend; the API supports `SERVER_PORT` and the frontend supports `PORT`. Use `/api/dashboard` as an API readiness check. Put HTTPS and access control in front of the deployment before using real financial data.
