# `profitable`

## [Unreleased]
- Add `Profitable.ttm_revenue` for trailing twelve-month revenue
- Add `Profitable.revenue_run_rate`, `estimated_arr_valuation`, `estimated_ttm_revenue_valuation`, and `estimated_revenue_run_rate_valuation`
- Make revenue metrics net of refunds when `amount_refunded` is present
- Make subscriber and MRR metrics distinguish between current billable subscriptions and historical period events
- Count `new_customers` from first monetization date rather than signup date
- Count `new_subscribers` / `new_mrr` from when a subscription becomes billable, not when a free trial starts
- Handle additional Pay status variants like `on_trial`, `cancelled`, and `deleted`
- Keep grace-period subscriptions billable until `ends_at`
- Exclude metered Stripe items from fixed run-rate MRR calculations
- Surface TTM revenue in the built-in dashboard

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
