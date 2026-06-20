# `profitable`

## [0.6.0] - 2026-06-20

Accuracy-focused release: every metric was re-audited line by line against the actual data `pay` (7.x–11.x) stores.

- **Fix canceled trials polluting nearly every flow metric**: a trial that was canceled without ever converting no longer counts in `total_subscribers`, `total_customers`, `new_customers`, `new_subscribers`, `new_mrr`, `churned_customers`, `churned_mrr`, `churn`, or the monthly/daily summaries. A subscription now only counts as ever-billable if it ended *after* billing started
- **Fix survivor bias in `monthly_summary` churn rates**: the churn denominator now includes subscribers who churned later inside the window, so early months no longer overstate churn
- **Fix summaries counting future trial conversions**: a trial scheduled to convert later this month/day no longer appears as a new subscriber (and new MRR) before it actually converts
- **Fix `paid: false` charges counting as revenue on SQLite**: JSON booleans surface as integers on SQLite (vs. text on PostgreSQL/MySQL); JSON extraction is now text-cast so all adapters filter identically (Rails 8 runs SQLite in production)
- **Handle Braintree/Lemon Squeezy statuses**: `expired` now counts as churn (at `ends_at`) instead of billable-forever, and `pending` (future start date, never billed) is excluded everywhere
- **Fix `time_to_next_mrr_milestone` returning a bare String**: it now returns a `NumericResult` like every other metric, so the documented `.to_readable` works (plain string comparisons still behave the same)
- **Fix Pay 7-9 schema compatibility for charge filtering**: revenue queries now only reference `pay_charges.object` when that column exists, so legacy `data`-only schemas do not crash
- **Fix paused subscriptions disappearing from lifecycle metrics**: paused subscriptions without a local pause start date remain excluded from current MRR, but still count as customers/subscribers if they had already become billable
- **Fix two small edge cases**: sub-dollar positive MRR no longer reports as "No MRR yet" for milestone messaging, and monthly churn denominators now match the inclusive period-start semantics used by `churn`
- Add `Profitable.mrr_at(date)` as the public historical MRR snapshot API, keeping the raw `calculate_mrr_at` helper private
- **Correct the processor coverage docs**: `pay` only stores subscription price payloads locally for Stripe, so Braintree/Paddle subscriptions contribute 0 to MRR-style metrics unless the payload is backfilled — the README previously overstated this; charge-based and lifecycle-based metrics remain fully portable across all processors
- DRY consolidation: MRR "billable right now" and "billable at date" are now literally the same query (`MrrCalculator.calculate` delegates to the shared snapshot), churn-event queries are defined once and reused by all metrics and summaries, and `subscription_data` has a single source of truth
- `MrrCalculator.calculate` streams subscriptions in batches (`find_each`) everywhere, keeping memory flat on large datasets
- Test coverage increased to ~98% line / ~90% branch, including regression tests for every bug above, exercised against Pay 7.3–11.x and Rails 7.2–8.1

## [0.5.0] - 2026-03-19
- Add `Profitable.ttm_revenue` for trailing twelve-month revenue
- Add `Profitable.ttm` as a founder-friendly alias for `ttm_revenue`
- Add `Profitable.revenue_run_rate`, `estimated_arr_valuation`, `estimated_ttm_revenue_valuation`, and `estimated_revenue_run_rate_valuation`
- Make revenue metrics net of refunds when `amount_refunded` is present
- Make subscriber and MRR metrics distinguish between current billable subscriptions and historical period events
- Count `new_customers` from first monetization date rather than signup date
- Count `new_subscribers` / `new_mrr` from when a subscription becomes billable, not when a free trial starts
- Handle additional Pay status variants like `on_trial`, `cancelled`, and `deleted`
- Keep grace-period subscriptions billable until `ends_at`
- Exclude metered Stripe items from fixed run-rate MRR calculations
- Surface TTM revenue in the built-in dashboard
- Extract shared metric logic to `lib/profitable/metrics.rb` for cleaner architecture

## [0.4.0] - 2026-02-10
- Add monthly summary (12mo) and daily summary (30d) tables to dashboard
- Add `period_data` method for efficient batch computation of period metrics
- Fix `new_mrr` counting incomplete/unpaid subscriptions (now only counts active)
- Fix `new_subscribers` not filtering out trialing/paused subscriptions
- DRY up period methods (churn, churned_customers, new_mrr, etc.) via `_in_period` delegation
- Optimize dashboard from ~176 to 38 queries (batch summary queries, precompute in controller)

## [0.3.0] - 2026-01-01
- Add Pay v10+ support, comprehensive Minitest test suite, and 16 critical bugfixes re: wrong calculations

## [0.2.3] - 2024-09-01

- Fix the `time_to_next_mrr_milestone` estimation and make it accurate to the day

## [0.2.2] - 2024-09-01

- Improve MRR calculations with prorated churned and new MRR (hopefully fixes bad churned MRR calculations)
- Only consider paid charges for all revenue calculations (hopefully fixes bad ARPC calculations)
- Add `multiple:` parameter as another option for `estimated_valuation` (same as `at:`, just syntactic sugar)

## [0.2.1] - 2024-08-31

- Add syntactic sugar for `estimated_valuation(at: "3x")`
- Now `estimated_valuation` also supports `Numeric`-only inputs like `estimated_valuation(3)`, so that @pretzelhands can avoid writing 3 extra characters and we embrace actual syntactic sugar instead of "syntactic saccharine" (sic.)

## [0.2.0] - 2024-08-31

- Initial production ready release

## [0.1.0] - 2024-08-29

- Initial test release (not production ready)
