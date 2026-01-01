# frozen_string_literal: true

require_relative "profitable/version"
require_relative "profitable/error"
require_relative "profitable/engine"

require_relative "profitable/mrr_calculator"
require_relative "profitable/numeric_result"
require_relative "profitable/json_helpers"

require "pay"
require "active_support/core_ext/numeric/conversions"
require "action_view"

module Profitable
  class << self
    include ActionView::Helpers::NumberHelper
    include Profitable::JsonHelpers

    DEFAULT_PERIOD = 30.days
    MRR_MILESTONES = [5, 10, 20, 30, 50, 75, 100, 200, 300, 400, 500, 1_000, 2_000, 3_000, 5_000, 10_000, 20_000, 30_000, 50_000, 83_333, 100_000, 250_000, 500_000, 1_000_000, 5_000_000, 10_000_000, 25_000_000, 50_000_000, 75_000_000, 100_000_000]

    def mrr
      NumericResult.new(MrrCalculator.calculate)
    end

    def arr
      NumericResult.new(calculate_arr)
    end

    def churn(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_churn(in_the_last), :percentage)
    end

    def all_time_revenue
      NumericResult.new(calculate_all_time_revenue)
    end

    def revenue_in_period(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_revenue_in_period(in_the_last))
    end

    def recurring_revenue_in_period(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_recurring_revenue_in_period(in_the_last))
    end

    def recurring_revenue_percentage(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_recurring_revenue_percentage(in_the_last), :percentage)
    end

    def estimated_valuation(multiplier = nil, at: nil, multiple: nil)
      actual_multiplier = multiplier || at || multiple || 3
      NumericResult.new(calculate_estimated_valuation(actual_multiplier))
    end

    def total_customers
      NumericResult.new(calculate_total_customers, :integer)
    end

    def total_subscribers
      NumericResult.new(calculate_total_subscribers, :integer)
    end

    def active_subscribers
      NumericResult.new(calculate_active_subscribers, :integer)
    end

    def new_customers(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_new_customers(in_the_last), :integer)
    end

    def new_subscribers(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_new_subscribers(in_the_last), :integer)
    end

    def churned_customers(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_churned_customers(in_the_last), :integer)
    end

    def new_mrr(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_new_mrr(in_the_last))
    end

    def churned_mrr(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_churned_mrr(in_the_last))
    end

    def average_revenue_per_customer
      NumericResult.new(calculate_average_revenue_per_customer)
    end

    def lifetime_value
      NumericResult.new(calculate_lifetime_value)
    end

    def mrr_growth(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_mrr_growth(in_the_last))
    end

    def mrr_growth_rate(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_mrr_growth_rate(in_the_last), :percentage)
    end

    def time_to_next_mrr_milestone
      current_mrr = (mrr.to_i) / 100  # Convert cents to dollars
      return "Unable to calculate. No MRR yet." if current_mrr <= 0

      next_milestone = MRR_MILESTONES.find { |milestone| milestone > current_mrr }
      return "Congratulations! You've reached the highest milestone." unless next_milestone

      monthly_growth_rate = calculate_mrr_growth_rate / 100
      return "Unable to calculate. Need more data or positive growth." if monthly_growth_rate <= 0

      # Convert monthly growth rate to daily growth rate
      daily_growth_rate = (1 + monthly_growth_rate) ** (1.0 / 30) - 1
      return "Unable to calculate. Growth rate too small." if daily_growth_rate <= 0

      # Calculate the number of days to reach the next milestone
      days_to_milestone = (Math.log(next_milestone.to_f / current_mrr) / Math.log(1 + daily_growth_rate)).ceil

      target_date = Time.current + days_to_milestone.days

      "#{days_to_milestone} days left to $#{number_with_delimiter(next_milestone)} MRR (#{target_date.strftime('%b %d, %Y')})"
    end

    private

    def paid_charges
      # Pay gem v10+ stores charge data in `object` column, older versions used `data`
      # We check both columns for backwards compatibility using database-agnostic JSON extraction
      #
      # Performance note: The COALESCE pattern may prevent index usage on some databases.
      # This is an acceptable tradeoff for backwards compatibility with Pay < 10.
      # For high-volume scenarios, consider adding a composite index or upgrading to Pay 10+
      # where only the `object` column is used.

      # Build JSON extraction SQL for both object and data columns
      paid_object = json_extract('pay_charges.object', 'paid')
      paid_data = json_extract('pay_charges.data', 'paid')
      status_object = json_extract('pay_charges.object', 'status')
      status_data = json_extract('pay_charges.data', 'status')

      Pay::Charge
        .where("pay_charges.amount > 0")
        .where(<<~SQL.squish, 'false', 'succeeded')
          (
            (COALESCE(#{paid_object}, #{paid_data}) IS NULL
             OR COALESCE(#{paid_object}, #{paid_data}) != ?)
          )
          AND
          (
            COALESCE(#{status_object}, #{status_data}) = ?
            OR COALESCE(#{status_object}, #{status_data}) IS NULL
          )
        SQL
    end

    def calculate_all_time_revenue
      paid_charges.sum(:amount)
    end

    def calculate_arr
      (mrr.to_f * 12).round
    end

    def calculate_estimated_valuation(multiplier = 3)
      multiplier = parse_multiplier(multiplier)
      (calculate_arr * multiplier).round
    end

    def parse_multiplier(input)
      case input
      when Numeric
        input.to_f
      when String
        if input.end_with?('x')
          input.chomp('x').to_f
        else
          input.to_f
        end
      else
        3.0 # Default multiplier if input is invalid
      end.clamp(0.1, 100) # Ensure multiplier is within a reasonable range
    end

    def calculate_churn(period = DEFAULT_PERIOD)
      start_date = period.ago

      # Count subscribers who were active AT the start of the period
      # (not just currently active, but active at that historical point)
      total_subscribers_start = Pay::Subscription
        .where('pay_subscriptions.created_at < ?', start_date)
        .where('pay_subscriptions.ends_at IS NULL OR pay_subscriptions.ends_at > ?', start_date)
        .where.not(status: ['trialing', 'paused'])
        .distinct
        .count('customer_id')

      churned = calculate_churned_customers(period)
      return 0 if total_subscribers_start == 0
      (churned.to_f / total_subscribers_start * 100).round(2)
    end

    def churned_subscriptions(period = DEFAULT_PERIOD)
      Pay::Subscription
        .includes(:customer)
        .select('pay_subscriptions.*, pay_customers.processor as customer_processor')
        .joins(:customer)
        .where(status: ['canceled', 'ended'])
        .where(ends_at: period.ago..Time.current)
    end

    def calculate_churned_customers(period = DEFAULT_PERIOD)
      churned_subscriptions(period).distinct.count('customer_id')
    end

    def calculate_churned_mrr(period = DEFAULT_PERIOD)
      start_date = period.ago
      end_date = Time.current

      # Churned MRR = full monthly rate of subscriptions that ended in the period
      # MRR is a rate, not revenue, so we don't prorate
      Pay::Subscription
        .includes(:customer)
        .select('pay_subscriptions.*, pay_customers.processor as customer_processor')
        .joins(:customer)
        .where(status: ['canceled', 'ended'])
        .where(ends_at: start_date..end_date)
        .sum do |subscription|
          MrrCalculator.process_subscription(subscription)
        end
    end

    def calculate_new_mrr(period = DEFAULT_PERIOD)
      start_date = period.ago
      end_date = Time.current

      # New MRR = full monthly rate of subscriptions created in the period
      # MRR is a rate, not revenue, so we don't prorate
      Pay::Subscription
        .active
        .includes(:customer)
        .select('pay_subscriptions.*, pay_customers.processor as customer_processor')
        .joins(:customer)
        .where(created_at: start_date..end_date)
        .where.not(status: ['trialing', 'paused'])
        .sum do |subscription|
          MrrCalculator.process_subscription(subscription)
        end
    end

    def calculate_revenue_in_period(period)
      paid_charges.where(created_at: period.ago..Time.current).sum(:amount)
    end

    def calculate_recurring_revenue_in_period(period)
      paid_charges
        .joins('INNER JOIN pay_subscriptions ON pay_charges.subscription_id = pay_subscriptions.id')
        .where(created_at: period.ago..Time.current)
        .sum(:amount)
    end

    def calculate_recurring_revenue_percentage(period)
      total_revenue = calculate_revenue_in_period(period)
      recurring_revenue = calculate_recurring_revenue_in_period(period)

      return 0 if total_revenue.zero?

      ((recurring_revenue.to_f / total_revenue) * 100).round(2)
    end

    def calculate_total_customers
      Pay::Customer.joins(:charges)
                   .merge(paid_charges)
                   .distinct
                   .count
    end

    def calculate_total_subscribers
      Pay::Customer.joins(:subscriptions).distinct.count
    end

    def calculate_active_subscribers
      Pay::Customer.joins(:subscriptions)
                   .where(pay_subscriptions: { status: 'active' })
                   .distinct
                   .count
    end

    def actual_customers
      Pay::Customer.joins("LEFT JOIN pay_subscriptions ON pay_customers.id = pay_subscriptions.customer_id")
                   .joins("LEFT JOIN pay_charges ON pay_customers.id = pay_charges.customer_id")
                   .where("pay_subscriptions.id IS NOT NULL OR pay_charges.amount > 0")
                   .distinct
    end

    def calculate_new_customers(period)
      actual_customers.where(created_at: period.ago..Time.current).count
    end

    def calculate_new_subscribers(period)
      # Count customers who got a NEW subscription in the period
      # (not customers created in the period, but subscriptions created in the period)
      Pay::Customer.joins(:subscriptions)
                   .where(pay_subscriptions: { created_at: period.ago..Time.current })
                   .distinct
                   .count
    end

    def calculate_average_revenue_per_customer
      paying_customers = calculate_total_customers
      return 0 if paying_customers.zero?
      (all_time_revenue.to_f / paying_customers).round
    end

    def calculate_lifetime_value
      # LTV = Monthly ARPU / Monthly Churn Rate
      # where ARPU (Average Revenue Per User) = MRR / active subscribers
      subscribers = calculate_active_subscribers
      return 0 if subscribers.zero?

      monthly_arpu = mrr.to_f / subscribers  # in cents
      churn_rate = churn.to_f / 100  # monthly churn as decimal (e.g., 5% = 0.05)
      return 0 if churn_rate.zero?

      (monthly_arpu / churn_rate).round  # LTV in cents
    end

    def calculate_mrr_growth(period = DEFAULT_PERIOD)
      new_mrr = calculate_new_mrr(period)
      churned_mrr = calculate_churned_mrr(period)
      new_mrr - churned_mrr
    end

    def calculate_mrr_growth_rate(period = DEFAULT_PERIOD)
      end_date = Time.current
      start_date = end_date - period

      start_mrr = calculate_mrr_at(start_date)
      end_mrr = calculate_mrr_at(end_date)

      return 0 if start_mrr == 0
      ((end_mrr.to_f - start_mrr) / start_mrr * 100).round(2)
    end

    def calculate_mrr_at(date)
      # Find subscriptions that were active AT the given date:
      # - Created before or on that date
      # - Not ended before that date (ends_at is nil OR ends_at > date)
      # - Not paused at that date
      # - Not in trialing status (trials don't count as MRR)
      Pay::Subscription
        .where('pay_subscriptions.created_at <= ?', date)
        .where('pay_subscriptions.ends_at IS NULL OR pay_subscriptions.ends_at > ?', date)
        .where('pay_subscriptions.pause_starts_at IS NULL OR pay_subscriptions.pause_starts_at > ?', date)
        .where.not(status: ['trialing', 'paused'])
        .includes(:customer)
        .select('pay_subscriptions.*, pay_customers.processor as customer_processor')
        .joins(:customer)
        .sum do |subscription|
          MrrCalculator.process_subscription(subscription)
        end
    end

  end
end
