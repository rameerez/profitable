# 💸 `profitable` - Calculate your MRR, churn & valuation

[![Gem Version](https://badge.fury.io/rb/profitable.svg)](https://badge.fury.io/rb/profitable)

Calculate the MRR, ARR, churn, total revenue & estimated valuation of your `pay`-powered Rails SaaS app, and display them in a simple dashboard.

## Why

[`pay`](https://github.com/pay-rails/pay) is the easiest way of handling payments in your Rails application. Think of `profitable` as the complement to `pay` that calculates business metrics like MRR, ARR, churn, total revenue & estimated valuation directly within your Rails application.

Usually, you would look into your Stripe Dashboard or query the Stripe API to know your MRR / ARR / churn – but if you're using `pay`, you already have that data available and auto synced to your own database. So we can leverage it to make handy, composable ActiveRecord queries that you can reuse in any part of your Rails app (dashboards, internal pages, reports, status messages, etc.)

Think doing something like: `"Your app is currently at $#{Profitable.mrr} MRR – Estimated to be worth $#{Profitable.valuation_estimate("3x")} at a 3x valuation"`

## Installation

Add this line to your application's Gemfile:
```ruby
gem 'profitable'
```

Then run `bundle install`.

## Main methods

All methods return numbers that can be converted to a nicely-formatted, human-readable string using the `to_readable` method.

### Revenue metrics

- `Profitable.mrr`: Monthly Recurring Revenue (MRR)
- `Profitable.arr`: Annual Recurring Revenue (ARR)
- `Profitable.all_time_revenue`: Total revenue since launch
- `Profitable.new_mrr(in_the_last: 30.days)`: New MRR added in the specified period
- `Profitable.churned_mrr(in_the_last: 30.days)`: MRR lost due to churn in the specified period
- `Profitable.average_revenue_per_customer`: Average revenue per customer (ARPU)
- `Profitable.lifetime_value`: Estimated customer lifetime value (LTV)

### Customer metrics

- `Profitable.total_customers`: Total number of customers
- `Profitable.total_subscribers`: Total number of active subscribers
- `Profitable.new_customers(in_the_last: 30.days)`: Number of new customers (both subscribers and non-subscribers) added in the specified period
- `Profitable.new_subscribers(in_the_last: 30.days)`: Number of new subscribers added in the specified period
- `Profitable.churned_customers(in_the_last: 30.days)`: Number of customers who churned in the specified period

### Other metrics

- `Profitable.churn(in_the_last: 30.days)`: Churn rate as a percentage
- `Profitable.estimated_valuation(multiplier = "3x")`: Estimated valuation based on ARR

### Usage examples

```ruby
# Get the current MRR
Profitable.mrr.to_readable # => "$1,234.56"

# Get the number of new customers in the last 60 days
Profitable.new_customers(in_the_last: 60.days).to_readable # => "42"

# Get the churn rate for the last quarter
Profitable.churn(in_the_last: 3.months).to_readable # => "12%"

# Get the estimated valuation at 5x ARR
Profitable.estimated_valuation("5x").to_readable # => "$500,000"

# Get the average revenue per customer
Profitable.average_revenue_per_customer.to_readable # => "$100.00"
```


All time-based methods default to a 30-day period if no time range is specified.

### Numeric values and readable format

Numeric values are returned in the same currency as your `pay` configuration. The `to_readable` method returns a human-readable format:

- Currency values are prefixed with "$" and formatted as currency.
- Percentage values are suffixed with "%" and formatted as percentages.
- Integer values are formatted with thousands separators but without currency symbols.

For more precise calculations, you can access the raw numeric value:
```ruby
# Returns the raw MRR integer value in cents
Profitable.mrr # => 123456
```

## Mount the `/profitable` dashboard

We also provide a simple dashboard with good defaults to see your main business metrics.

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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## TODO
- [ ] Support other currencies other than USD
- [ ] Support for multiple plans (churn by plan, MRR by plan, etc)
- [ ] Make sure other payment processors other than Stripe work as intended
- [ ] account for subscription upgrades/downgrades within a period

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/profitable. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
