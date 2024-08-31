# frozen_string_literal: true

require_relative "profitable/version"
require_relative "profitable/error"
require_relative "profitable/engine"

require_relative "profitable/mrr_calculator"
require_relative "profitable/numeric_result"

require "pay"
require "active_support/core_ext/numeric/conversions"
require "action_view"

module Profitable
  class << self
    include ActionView::Helpers::NumberHelper

    DEFAULT_PERIOD = 30.days
    MRR_MILESTONES = [100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000]

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

    def estimated_valuation(multiplier = "3x")
      NumericResult.new(calculate_estimated_valuation(multiplier))
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
      current_mrr = (mrr.to_i)/100
      next_milestone = MRR_MILESTONES.find { |milestone| milestone > current_mrr }
      return "Congratulations! You've reached the highest milestone." unless next_milestone

      growth_rate = calculate_mrr_growth_rate
      return "Unable to calculate. Need more data or positive growth." if growth_rate <= 0

      months_to_milestone = (Math.log(next_milestone.to_f / current_mrr) / Math.log(1 + growth_rate)).ceil
      days_to_milestone = months_to_milestone * 30

      return "#{days_to_milestone} days left to $#{number_with_delimiter(next_milestone)} MRR (#{(Time.current + days_to_milestone.days).strftime('%b %d, %Y')})"
    end

    private

    def paid_charges
      Pay::Charge.where("pay_charges.data ->> 'paid' = ?", 'true')
    end

    def calculate_all_time_revenue
      paid_charges.sum(:amount)
    end

    def calculate_arr
      (mrr.to_f * 12).round
    end

    def calculate_estimated_valuation(multiplier = "3x")
      multiplier = multiplier.to_s.gsub('x', '').to_f
      (calculate_arr * multiplier).round
    end

    def calculate_churn(period = DEFAULT_PERIOD)
      start_date = period.ago
      total_subscribers_start = Pay::Subscription.active.where('created_at < ?', start_date).distinct.count('customer_id')
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
      churned_subscriptions(period).sum do |subscription|
        MrrCalculator.process_subscription(subscription)
      end
    end

    def calculate_new_mrr(period = DEFAULT_PERIOD)
      new_subscriptions = Pay::Subscription
        .active
        .where(pay_subscriptions: { created_at: period.ago..Time.current })
        .where.not(status: ['trialing', 'paused'])
        .includes(:customer)
        .select('pay_subscriptions.*, pay_customers.processor as customer_processor')
        .joins(:customer)

      new_subscriptions.sum do |subscription|
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
      actual_customers.count
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
      Pay::Customer.joins(:subscriptions)
                   .where(created_at: period.ago..Time.current)
                   .distinct
                   .count
    end

    def calculate_average_revenue_per_customer
      return 0 if total_customers.zero?
      (all_time_revenue.to_f / total_customers).round
    end

    def calculate_lifetime_value
      return 0 if total_customers.zero?
      churn_rate = churn.to_f / 100
      return 0 if churn_rate.zero?
      (average_revenue_per_customer.to_f / churn_rate).round
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
      Pay::Subscription
        .active
        .where('pay_subscriptions.created_at <= ?', date)
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
