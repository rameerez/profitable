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

- `Profitable.mrr`: monthly recurring revenue
- `Profitable.arr`: annual recurring revenue
- `Profitable.churn`: churn rate
- `Profitable.all_time_revenue`: total revenue since launch
- `Profitable.estimated_valuation`: defaults to 3x the current ARR – you can pass custom multipliers, like `Profitable.estimated_valuation("5x")`

Numeric values are returned in the same currency as your `pay` configuration. For numeric values, there is a `to_readable` method that returns a human readable format.

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

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/profitable. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
