# Query timings

Every executable query in [`04_queries.sql`](04_queries.sql) (DEQ-01 to DEQ-10), run three times with `EXPLAIN (ANALYZE, BUFFERS)`. Each time is PostgreSQL's own `Execution Time` from the saved plan; the raw output of all three runs is in [`plans/`](plans/), one file per query.

## Results

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan type |
|-------|------|--------------|-----------:|-----------:|-----------:|-------------:|-----------|
| [DEQ-01](plans/DEQ-01.txt) | WRITE | Create a user (registration) | 0.277 | 0.098 | 0.039 | 0.138 | — (Insert, no scan) |
| [DEQ-02](plans/DEQ-02.txt) | READ | Look up a phone account | 0.019 | 0.013 | 0.010 | 0.014 | Index Scan (`users_phone_key`) |
| [DEQ-03](plans/DEQ-03.txt) | WRITE | Register a phone browser as a device | 0.556 | 0.092 | 0.051 | 0.233 | — (Insert, no scan) |
| [DEQ-04](plans/DEQ-04.txt) | WRITE | Start a one-time QR request | 0.329 | 0.124 | 0.260 | 0.238 | — (Insert, no scan) |
| [DEQ-05](plans/DEQ-05.txt) | READ | Find a request by the token scanned from the QR code | 0.034 | 0.015 | 0.014 | 0.021 | Index Scan (`login_requests_token_key`) |
| [DEQ-06](plans/DEQ-06.txt) | WRITE | Approve once and create the browser session (2 statements) | 0.484 | 0.069 | 0.056 | 0.203 | Index Scan (`login_requests_pkey`) + Insert |
| [DEQ-07](plans/DEQ-07.txt) | READ | List active browser sessions for the signed-in user | 0.023 | 0.005 | 0.003 | 0.010 | Index Scan (`sessions_user_type_revoked_idx`) + Sort |
| [DEQ-08](plans/DEQ-08.txt) | WRITE | Revoke one of the user's browser sessions | 0.108 | 0.017 | 0.011 | 0.045 | Index Scan (`sessions_pkey`) |
| [DEQ-09](plans/DEQ-09.txt) | READ | Check the session named by a verified JWT cookie | 0.024 | 0.004 | 0.003 | 0.010 | Index Scan (`sessions_pkey`) |
| [DEQ-10](plans/DEQ-10.txt) | WRITE | Expire old pending requests (3,334 rows) | 13.130 | 15.369 | 17.072 | 15.190 | Bitmap Index Scan (`login_requests_status_expiry_idx`) + Bitmap Heap Scan |

DEQ-11 is a comment listing the indexes, not a query, so it has no timing.

## What the plans show

- **No query reads a whole table.** Every lookup uses an index: the unique indexes on `phone` and `token`, the primary keys, `sessions_user_type_revoked_idx` for the session list, and `login_requests_status_expiry_idx` for expiring requests.
- **DEQ-10 is the slowest, and the index is not the reason.** The index finds the 3,334 expired pending requests in under 0.5 ms (`Bitmap Heap Scan … actual time=0.069..0.405` in run 1). The rest of the time is writing 3,334 updated rows. Its time rose from run 1 to run 3; a likely cause is that each rolled-back run leaves 3,334 dead row versions that the next run has to step over (no `VACUUM` between runs).
- **DEQ-06 is two statements in one transaction.** Its run time is the `UPDATE` plus the `INSERT`; both plans and the sum are in [`plans/DEQ-06.txt`](plans/DEQ-06.txt). The `UPDATE` matched 1 row in every run, so the `INSERT` is the one the app would run.
- **Writes include foreign-key checks.** The `Trigger for constraint …` lines in the write plans are part of `Execution Time` (for example 0.259 ms of DEQ-03 run 1).
- **Run 1 is usually slowest.** All three runs of a query share one connection; run 1 loads the table and index details that runs 2 and 3 then reuse (`Planning: Buffers` appears only in run 1, except DEQ-03 and DEQ-04, where it appears in no run).

## How the timings were taken

| | DEQ-01 to DEQ-05 | DEQ-06 to DEQ-10 |
|---|---|---|
| Measured | 2026-11-23 13:17 UTC (merged in PR #7) | 2026-11-23 18:56 UTC (this file's PR) |
| PostgreSQL | 14.23 (Homebrew build) | 14.23 (conda-forge build), local throwaway cluster, default settings |
| Schema | Prisma migration (index names in the plans match it) | `prisma/migrations/20261121000000_init/migration.sql` |
| Data | users=10001, devices=15000, login_requests=20000, sessions=6000 | Same counts, from the same synthetic-data SQL script (ids are derived from `md5`, so the rows are identical) plus the demo user `+15551234567`; `VACUUM ANALYZE` after loading |

- Each query ran 3 times with `EXPLAIN (ANALYZE, BUFFERS)`, all three on one database connection; the times above are the `Execution Time` lines, and the average is their mean.
- Write queries ran inside `BEGIN … ROLLBACK`, so every run saw the same data.
- Parameter values are written into the statements as literals; each plan file lists them.
- Pending requests in the synthetic data expire 2 minutes after loading, so DEQ-06 to DEQ-10 ran straight after the data load (all runs finished 0.2 s after it).
