# 💸 `profitable` - MRR dashboard & SaaS metrics for your Rails app

[![Gem Version](https://badge.fury.io/rb/profitable.svg)](https://badge.fury.io/rb/profitable) [![Build Status](https://github.com/rameerez/profitable/workflows/Tests/badge.svg)](https://github.com/rameerez/profitable/actions)

> [!TIP]
> **🚀 Ship your next Rails app 10x faster!** I've built **[RailsFast](https://railsfast.com/?ref=profitable)**, a production-ready Rails boilerplate template that comes with everything you need to launch a software business in days, not weeks. Go [check it out](https://railsfast.com/?ref=profitable)!

`profitable` allows you to calculate the MRR, ARR, churn, LTV, ARPU, total revenue & estimated valuation of your `pay`-powered Rails SaaS app, and display them in a simple dashboard. It also provides handy methods you can use independently if you don't want the full dashboard.

![Profitable gem main dashboard](profitable.webp)

## Why

[`pay`](https://github.com/pay-rails/pay) is the easiest way of handling payments in your Rails application. Think of `profitable` as the complement to `pay` that calculates business SaaS metrics like MRR, ARR, churn, total revenue & estimated valuation directly within your Rails application.

Usually, you would look into your Stripe Dashboard or query the Stripe API to know your MRR / ARR / churn – but when you're using `pay`, you already have that data available and auto synced to your own database. So we can leverage it to make handy, composable ActiveRecord queries that you can reuse in any part of your Rails app (dashboards, internal pages, reports, status messages, etc.)

Think doing something like: `"Current MRR: $#{Profitable.mrr}"` or `"Your app is worth $#{Profitable.valuation_estimate("3x")} at a 3x valuation"`

## Installation

Add this line to your application's Gemfile:
```ruby
gem 'profitable'
```

Then run `bundle install`.

Provided you have a valid [`pay`](https://github.com/pay-rails/pay) installation (`Pay::Customer`, `Pay::Subscription`, `Pay::Charge`, etc.) everything is already set up and you can just start using [`Profitable` methods](#main-profitable-methods) right away.

Current MRR processor coverage is verified for `stripe`, `braintree`, `paddle_billing`, and `paddle_classic`.

For Stripe, metered subscription items are intentionally excluded from fixed run-rate metrics like `mrr`, `arr`, `new_mrr`, and `churned_mrr`.

> [!IMPORTANT]
> `profitable` does **not** yet normalize MRR for every processor that `pay` supports.
> If a subscription comes from an unsupported processor such as `lemon_squeezy`, it will currently contribute `0` to processor-adapter-dependent metrics until an adapter is added.
>
> Verified processor-adapter coverage today:
> - `stripe`
> - `braintree`
> - `paddle_billing`
> - `paddle_classic`
>
> Metrics that depend on processor-specific subscription amount parsing include `mrr`, `arr`, `new_mrr`, `churned_mrr`, `mrr_growth`, `mrr_growth_rate`, `lifetime_value`, `time_to_next_mrr_milestone`, and MRR-derived fields in summaries.
>
> Metrics based primarily on `Pay::Charge` and generic subscription lifecycle fields are much more portable across processors, including `all_time_revenue`, `revenue_in_period`, `ttm_revenue`, `revenue_run_rate`, customer counts, subscriber counts, and churn calculations.

## Mount the `/profitable` dashboard

`profitable` also provides a simple dashboard to see your main business metrics.

In your `config/routes.rb` file, mount the `profitable` engine:
```ruby
mount Profitable::Engine => '/profitable'
```

It's a good idea to make sure you're adding some sort of authentication to the `/profitable` route to avoid exposing sensitive information:
```ruby
authenticate :user, ->(user) { user.admin? } do
  mount Profitable::Engine => '/profitable'
end
```

You can now navigate to `/profitable` to see your app's business metrics like MRR, ARR, churn, etc.

## Main `Profitable` methods

All methods return numbers that can be converted to a nicely-formatted, human-readable string using the `to_readable` method.

### Revenue metrics

- `Profitable.mrr`: Monthly Recurring Revenue (MRR) from subscriptions that are billable right now
- `Profitable.arr`: Annual Recurring Revenue (ARR), calculated as current `mrr * 12`, not trailing revenue
- `Profitable.ttm`: Founder-friendly shorthand alias for `ttm_revenue`
- `Profitable.ttm_revenue`: Trailing twelve-month revenue, net of refunds when `amount_refunded` is present
- `Profitable.revenue_run_rate(in_the_last: 30.days)`: Recent revenue annualized (useful for TrustMRR-style revenue multiples)
- `Profitable.all_time_revenue`: Net revenue since launch
- `Profitable.revenue_in_period(in_the_last: 30.days)`: Net revenue (recurring and non-recurring) in the specified period
- `Profitable.recurring_revenue_in_period(in_the_last: 30.days)`: Only recurring revenue in the specified period
- `Profitable.recurring_revenue_percentage(in_the_last: 30.days)`: Percentage of revenue that is recurring in the specified period
- `Profitable.new_mrr(in_the_last: 30.days)`: Full MRR from subscriptions that first became billable in the specified period
- `Profitable.churned_mrr(in_the_last: 30.days)`: MRR lost due to churn in the specified period
- `Profitable.average_revenue_per_customer`: Average revenue per customer (ARPC)
- `Profitable.lifetime_value`: Estimated customer lifetime value (LTV)
- `Profitable.estimated_valuation(at: "3x")`: ARR-based valuation heuristic
- `Profitable.estimated_arr_valuation(at: "3x")`: Explicit ARR-based valuation heuristic
- `Profitable.estimated_ttm_revenue_valuation(at: "2x")`: TTM revenue-based valuation heuristic
- `Profitable.estimated_revenue_run_rate_valuation(at: "2x", in_the_last: 30.days)`: Recent revenue run-rate valuation heuristic

### Customer metrics

- `Profitable.total_customers`: Total number of customers who have ever monetized through a paid charge or a paid subscription state
- `Profitable.total_subscribers`: Total number of customers who have ever reached a paid subscription state (trial-only subscriptions do not count)
- `Profitable.active_subscribers`: Number of customers with subscriptions that are billable right now
- `Profitable.new_customers(in_the_last: 30.days)`: Number of first-time customers added in the period based on first monetization date, not signup date
- `Profitable.new_subscribers(in_the_last: 30.days)`: Number of customers whose subscriptions first became billable in the specified period
- `Profitable.churned_customers(in_the_last: 30.days)`: Number of customers who churned in the specified period

### Other metrics

- `Profitable.churn(in_the_last: 30.days)`: Churn rate for the specified period
- `Profitable.mrr_growth_rate(in_the_last: 30.days)`: MRR growth rate for the specified period
- `Profitable.time_to_next_mrr_milestone`: Estimated time to reach the next MRR milestone

### Growth metrics

- `Profitable.mrr_growth(in_the_last: 30.days)`: Calculates the absolute MRR growth over the specified period
- `Profitable.mrr_growth_rate(in_the_last: 30.days)`: Calculates the MRR growth rate (as a percentage) over the specified period

### Milestone metrics

- `Profitable.time_to_next_mrr_milestone`: Estimates the time to reach the next MRR milestone

### Usage examples

```ruby
# Get the current MRR
Profitable.mrr.to_readable # => "$1,234"

# Get the number of new customers in the last 60 days
Profitable.new_customers(in_the_last: 60.days).to_readable # => "42"

# Get the churn rate for the last quarter
Profitable.churn(in_the_last: 3.months).to_readable # => "12%"

# You can specify the precision of the output number (no decimals by default)
Profitable.new_mrr(in_the_last: 24.hours).to_readable(2) # => "$123.45"

# Get the estimated valuation at 5x ARR (defaults to 3x if no multiple is specified)
Profitable.estimated_arr_valuation(multiple: 5).to_readable # => "$500,000"

# Get trailing twelve-month revenue
Profitable.ttm_revenue.to_readable # => "$123,456"

# Founder-friendly shorthand for trailing twelve-month revenue
Profitable.ttm.to_readable # => "$123,456"

# Get recent revenue annualized (useful for TrustMRR-style revenue multiples)
Profitable.revenue_run_rate(in_the_last: 30.days).to_readable # => "$96,000"

# `estimated_valuation` remains as a backwards-compatible alias of `estimated_arr_valuation`
Profitable.estimated_valuation(at: "4.5x").to_readable # => "$450,000"

# Be explicit about the denominator when comparing marketplace comps
Profitable.estimated_ttm_revenue_valuation(2).to_readable
Profitable.estimated_revenue_run_rate_valuation(2.7, in_the_last: 30.days).to_readable

# Get the time to next MRR milestone
Profitable.time_to_next_mrr_milestone.to_readable  # => "26 days left to $10,000 MRR"
```

All time-based methods default to a 30-day period if no time range is specified.

### Numeric values and readable format

Numeric values are returned in the same currency as your `pay` configuration. The `to_readable` method returns a human-readable format:

- Currency values are prefixed with "$" and formatted as currency.
- Percentage values are suffixed with "%" and formatted as percentages.
- Integer values are formatted with thousands separators but without currency symbols.

For more precise calculations, you can access the raw numeric value:
```ruby
# Returns the raw MRR integer value in cents (123456 equals $1.234,56)
Profitable.mrr # => 123456
```

Revenue methods are net of refunds when `amount_refunded` is present on `pay_charges`.

### Notes on specific metrics

- `mrr_growth_rate`: This calculation compares the MRR at the start and end of the specified period. It assumes a linear growth rate over the period, which may not reflect short-term fluctuations. For more accurate results, consider using shorter periods or implementing a more sophisticated growth calculation method if needed.
- `time_to_next_mrr_milestone`: This estimation is based on the current MRR and the recent growth rate. It assumes a constant growth rate, which may not reflect real-world conditions. The calculation may be inaccurate for very new businesses or those with irregular growth patterns.

## Metric guide: TTM, Revenue, Profit, ARR, and MRR

`profitable` exposes both standard recurring revenue metrics (`MRR`, `ARR`) and trailing actuals (`TTM revenue`) on purpose.

These metrics are related, but they are not interchangeable:

| Metric | What it means | Best for | What it is **not** |
| --- | --- | --- | --- |
| `MRR` | Monthly Recurring Revenue from subscriptions that are billable right now | Operating cadence, near-term momentum, tracking upgrades/downgrades | It's **not** monthly cash collected from all sources |
| `ARR` | Annual Recurring Revenue, calculated as the current recurring base annualized | Forecasting recurring scale, board/investor reporting, recurring-revenue quality | It's **not** a historical last-12-month revenue |
| `MRR * 12` | Simple annualization of the current monthly recurring base | Fast ARR approximation when the base is normalized monthly | It's **not** TTM revenue or TTM profit |
| `TTM revenue` | Actual revenue collected over the last 12 months | Buyer-facing historical actuals, smoothing seasonality, sanity-checking ARR | It's **not** a forward recurring run-rate |
| `TTM profit` | Actual profit over the last 12 months | Small bootstrapped SaaS exits, ROI-minded buyers, earnings-based multiples | It's **not** something `profitable` can derive from `pay` alone |

### The distinction

- `ARR` is a run-rate metric. Stripe describes it as revenue you "expect to earn in a year" and notes that `ARR = MRR × 12`.
- `TTM` is a trailing metric. CFI defines it as the "most recent 12-month period" and uses it for reported actuals such as revenue and EBITDA.
- `TTM revenue` tells you what customers actually paid over the last year.
- `TTM profit` tells you what the business actually kept after costs. This is often what smaller acquisition buyers care about most, but it requires cost data outside `pay`.
- In acquire-style market reports, `TTM` can refer to **both** `TTM profit` and `TTM revenue` depending on the chart. The denominator must always be stated explicitly.
- In `profitable`, the shorthand method `ttm` is defined to mean `ttm_revenue` because the gem does not yet model costs or profit.

In other words:

- `ARR` answers: "What is my current recurring run-rate? What do I expect to earn in a year?"
- `TTM revenue` answers: "What did I actually collect over the last year?"

### What `profitable` calculates

- `Profitable.mrr`: Monthly Recurring Revenue (MRR) from subscriptions that are billable right now
- `Profitable.arr`: Annual Recurring Revenue (ARR), calculated from current MRR
- `Profitable.ttm`: shorthand alias for `ttm_revenue`
- `Profitable.ttm_revenue`: trailing 12-month revenue, net of refunds when `amount_refunded` is present
- `Profitable.revenue_run_rate`: recent revenue annualized to a yearly run-rate
- `Profitable.estimated_valuation`: ARR-multiple heuristic
- `Profitable.estimated_ttm_revenue_valuation`: TTM revenue heuristic
- `Profitable.estimated_revenue_run_rate_valuation`: recent revenue run-rate heuristic

`profitable` does **not** calculate `TTM profit`, because payroll, contractor spend, hosting, support, software tools, taxes, and owner add-backs do not live inside `pay`.

### Which metric matters in which situation?

- If you're operating the business week to week: `MRR` is usually the best pulse metric.
- If you want to understand your current subscription run-rate: `ARR` is the right metric.
- If you're preparing buyer materials for a bootstrapped SaaS exit: add `TTM revenue` and your own `TTM profit`.
- If your business has meaningful one-time revenue, services, setup fees, or seasonal swings: `TTM revenue` matters more than `ARR`.
- If you are speaking to serious SaaS buyers about revenue quality: pair `ARR` with churn, growth, concentration, and margins.

### What the market says

These are short excerpts from current market and finance sources, followed by why they matter for `profitable`.

- [Acquire.com Biannual Multiples Report (Jan 2026)](https://blog.acquire.com/acquire-com-biannual-acquisition-multiples-report-jan-2026/): "anchor valuation on profit"
  Acquire says the January 2026 report is focused "entirely on profit multiples," which is highly relevant for smaller bootstrapped SaaS exits.
  In the same report, some visual breakdowns segment businesses by `TTM revenue` bands, so it is important not to assume one bare `TTM` label means the same thing everywhere.

- [Acquire.com Biannual Multiples Report, January 2024](https://blog.acquire.com/wp-content/uploads/2024/01/Acquire-Biannual-Multiples-Report-Jan-2024.pdf): "4.3x TTM profit"
  The earlier report gives a concrete historical benchmark for how these profit multiples looked on the marketplace.

- [Acquire.com 2025 webinar recap](https://blog.acquire.com/the-secrets-behind-2024s-biggest-exits-webinar-recap/): "$100k-$1M in TTM revenue"
  Acquire says that cohort averaged `4.35x`, which is a useful live-market anchor for micro-SaaS exits.

- [Acquire.com SaaS valuation multiples guide](https://blog.acquire.com/saas-valuation-multiples/): "5x to 15x ARR"
  Stronger recurring SaaS businesses are also routinely discussed in ARR-multiple terms, especially when growth and retention are strong.

- [Stripe on ARR](https://stripe.com/us/resources/more/acv-vs-arr-what-each-metric-really-means-and-when-they-matter): "ARR = £50,000 x 12 = £600,000"
  This is the clearest shorthand for why `ARR` is a run-rate, not a trailing actual.

- [CFI on TTM](https://corporatefinanceinstitute.com/resources/valuation/railing-twelve-months-ttm-definition/): "most recent 12-month period"
  This is why `ttm_revenue` belongs beside `arr`: it measures trailing actuals, not a projection.

- [Quiet Light on selling SaaS](https://quietlight.com/sell-your-saas-business-for-the-best-price/): "EBITDA or SDE"
  Quiet Light explicitly says smaller SaaS businesses are often valued on earnings, not revenue, which is why `TTM profit` matters.

- [Quiet Light on larger SaaS](https://quietlight.com/sell-your-saas-business-for-the-best-price/): "ARR of $1M or more"
  The same source says larger SaaS businesses may qualify for revenue multiples, which is why `ARR` becomes more important as the business scales.

- [Software Equity Group, 3Q25 SaaS M&A](https://softwareequity.com/blog/saas-ma-deal-volume-and-valuations): "5.4x"
  SEG reported average SaaS M&A valuations of `5.4x` revenue in 3Q25, which is useful context for larger, more institutional software transactions.

- [TrustMRR live listing example](https://trustmrr.com/startup/appalchemy): "$164,819 TTM revenue"
  Live marketplaces increasingly show `TTM revenue`, `TTM profit`, and `ARR` side by side, which matches how buyers actually compare deals.

- [TrustMRR FAQ](https://trustmrr.com/faq): "asking price divided by annualized revenue"
  TrustMRR explicitly defines its marketplace multiple as asking price divided by `last 30 days revenue × 12`, so its multiple is a revenue run-rate multiple, not an ARR multiple.

- [TrustMRR FAQ](https://trustmrr.com/faq): "Only aggregate revenue metrics"
  TrustMRR says it only pulls revenue-level aggregates from payment providers, which is another reason its native multiple is revenue-based rather than profit-based.

- [TrustMRR FAQ](https://trustmrr.com/faq): "profit margin for the last 30 days"
  TrustMRR asks sellers to provide profit margin separately when listing for sale, which reinforces that profit-based heuristics need cost inputs outside the payment provider.

### How to use these metrics responsibly

- `estimated_valuation` is intentionally simple. It is kept as a backwards-compatible ARR heuristic. Prefer `estimated_arr_valuation` in new code when you want the denominator to be explicit.
- Do not compare an ARR multiple and a TTM profit multiple as if they were the same kind of number. They are based on different denominators.
- A `4x TTM profit` deal, a `2x TTM revenue` deal, and an `8x ARR` deal can all describe reasonable SaaS outcomes in different buyer segments.
- If two businesses both have `$300k ARR`, the one with lower churn, better margins, lower concentration, and cleaner growth usually deserves the higher multiple.
- If two businesses both have `$300k TTM revenue`, the one with stronger profit and more recurring revenue usually deserves the higher price.

### Typical multiples by SaaS type and size

These are rough, source-backed heuristics. They are not interchangeable.

| SaaS profile | Common denominator | Rough multiple | Source |
| --- | --- | --- | --- |
| Smaller profitable SaaS on Acquire.com (2024-2025 confirmed transactions) | `TTM profit` | `3.9x` median | [Acquire.com Jan 2026 report](https://blog.acquire.com/acquire-com-biannual-acquisition-multiples-report-jan-2026/) |
| Micro-SaaS under `$100k` TTM revenue | `TTM profit` | `3.55x` average | [Acquire.com webinar recap](https://blog.acquire.com/the-secrets-behind-2024s-biggest-exits-webinar-recap/) |
| Micro-SaaS with `$100k-$1M` TTM revenue | `TTM profit` | `4.35x` average | [Acquire.com webinar recap](https://blog.acquire.com/the-secrets-behind-2024s-biggest-exits-webinar-recap/) |
| TrustMRR marketplace listings | `Annualized last 30d revenue` | often roughly `0.6x-5.5x` ask multiples | [TrustMRR homepage snapshot](https://trustmrr.com/) |
| Mid-6-figure ARR SaaS | `TTM revenue` | `2x-4x` revenue | [Acquire.com founder-driven acquisition recap](https://blog.acquire.com/how-founders-can-drive-their-own-acquisition-process-webinar-recap/) |
| Older Acquire.com SaaS baseline | `TTM revenue` or `TTM profit` | `2-3x revenue` or `5x profit` | [Acquire.com 7-8 figures webinar recap](https://blog.acquire.com/how-to-sell-your-company-playbook-webinar/) |
| Strong recurring SaaS with high growth and retention | `ARR` | `5x-15x ARR` | [Acquire.com SaaS valuation multiples guide](https://blog.acquire.com/saas-valuation-multiples/) |

How to read this table:

- Smaller bootstrapped SaaS buyers on Acquire-style marketplaces often underwrite on `TTM profit`.
- If profit is low or intentionally reinvested, buyers may fall back to `TTM revenue`.
- TrustMRR listing multiples are a secondary comparison set: they are based on recent revenue run-rate, specifically `last 30 days revenue × 12`.
- Higher-quality SaaS with real scale, low churn, and strong growth is more likely to be discussed in `ARR` terms.

### Rough valuation formulas from `profitable`

You can only multiply a metric by a multiple if the denominator matches.

#### 1. ARR multiple

This is already built into the gem:

```ruby
# Example: 6x ARR
Profitable.estimated_arr_valuation(multiple: 6).to_readable
```

Use this when:

- your business is strongly recurring,
- churn and retention are solid,
- and you want a run-rate-based heuristic.

#### 2. TTM revenue multiple

This is useful when buyers care more about trailing actuals than annualized run-rate:

```ruby
ttm_revenue_cents = Profitable.ttm_revenue.to_i

low_estimate_cents  = (ttm_revenue_cents * 2.0).round
high_estimate_cents = (ttm_revenue_cents * 4.0).round
```

Use this when:

- the business has meaningful one-time revenue,
- profit is thin because you are reinvesting,
- or the buyer is thinking in revenue-band terms.

#### 2b. Recent revenue run-rate multiple

This is the closest match to TrustMRR-style marketplace multiples:

```ruby
# Default: annualized last-30-days revenue
Profitable.revenue_run_rate.to_readable
Profitable.estimated_revenue_run_rate_valuation(2.7).to_readable
```

Use this when:

- you're comparing against TrustMRR listings,
- the market is quoting a multiple on recent revenue rather than ARR,
- and you want the denominator to match the marketplace comp.

#### 3. TTM profit multiple

`profitable` cannot calculate this yet because it does not know your costs.

```ruby
# You need to compute this outside of profitable:
ttm_profit_cents = your_ttm_profit_cents

low_estimate_cents  = (ttm_profit_cents * 3.5).round
high_estimate_cents = (ttm_profit_cents * 4.35).round
```

Use this when:

- the business is a smaller profitable micro-SaaS,
- the buyer is focused on ROI and cash flow,
- or you're comparing yourself to Acquire.com-style marketplace comps.

## Development

After checking out the repo, install dependencies:

```bash
bundle install
```

### Running Tests

The gem includes a Minitest test suite. Run it with:

```bash
# Run all tests
bundle exec rake test
```

### Testing Against Multiple Pay Gem Versions

This gem uses [Appraisal](https://github.com/thoughtbot/appraisal) to test against multiple versions of the Pay gem, ensuring compatibility across Pay 7.x through 11.x.

**Generate appraisal gemfiles:**

```bash
bundle exec appraisal install
```

**Run tests against a specific Pay version:**

```bash
# Test against Pay 10.x
bundle exec appraisal pay-10.0 rake test

# Test against Pay 11.x
bundle exec appraisal pay-11.0 rake test
```

**Run tests against all Pay versions:**

```bash
bundle exec appraisal rake test
```

### Database Compatibility

Tests run on SQLite by default, but the gem supports:
- PostgreSQL (9.3+)
- MySQL (5.7.9+)
- MariaDB (10.2.7+)
- SQLite (3.9.0+)

The gem automatically detects your database adapter and uses the appropriate JSON query syntax.

To install this gem onto your local machine, run `bundle exec rake install`.

## TODO
- [ ] Calculate split by plan / add support for multiple plans (churn by plan, MRR by plan, etc) – not just aggregated
- [ ] Calculate MRR expansion (plan upgrades), contraction (plan downgrades), etc. like Stripe does
- [ ] Add active customers (not just total customers)
- [ ] Add % of change over last period (this period vs last period)
- [ ] Calculate total period revenue vs period recurring revenue (started, but not sure if accurate)
- [ ] Add revenue last month to dashboard (not just past 30d, like previous month)
- [ ] Support other currencies other than USD (convert currencies)
- [ ] Make sure other payment processors other than Stripe work as intended (Paddle, Braintree, etc. – I've never used them)
- [ ] Add a way to input monthly costs (maybe via config file?) so that we can calculate a profit margin %
- [ ] Allow dashboard configuration via config file (which metrics to show, etc.)
- [ ] Return a JSON in the dashboard endpoint with main metrics (for monitoring / downstream consumption)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/profitable. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
