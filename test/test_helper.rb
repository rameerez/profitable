# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# SimpleCov must be loaded BEFORE any application code
# Configuration is auto-loaded from .simplecov file
require "simplecov"

require "bundler/setup"
require "active_record"
require "active_support/all"
require "action_view"
require "minitest/autorun"
require "minitest/mock"
require "minitest/reporters"
require "mocha/minitest"

# Configure Minitest reporters for better output
Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(color: true)]

# Stub Rails module for standalone testing
module Rails
  def self.logger
    @logger ||= Logger.new(nil)
  end

  def self.root
    Pathname.new(File.expand_path("..", __dir__))
  end

  def self.env
    ActiveSupport::StringInquirer.new("test")
  end
end

# Set up an in-memory SQLite database for testing
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Silence ActiveRecord logs during tests
ActiveRecord::Base.logger = nil

# Create the schema for Pay models
# Note: Using json instead of jsonb for SQLite compatibility
ActiveRecord::Schema.define do
  create_table :pay_customers, force: true do |t|
    t.string :owner_type
    t.integer :owner_id
    t.string :processor
    t.string :processor_id
    t.boolean :default
    t.json :data
    t.datetime :deleted_at
    t.timestamps
  end

  create_table :pay_subscriptions, force: true do |t|
    t.references :customer, foreign_key: { to_table: :pay_customers }
    t.string :name
    t.string :processor_id
    t.string :processor_plan
    t.integer :quantity, default: 1
    t.string :status
    t.datetime :current_period_start
    t.datetime :current_period_end
    t.datetime :trial_ends_at
    t.datetime :ends_at
    t.datetime :pause_starts_at
    t.datetime :pause_resumes_at
    t.json :data
    t.json :object  # Pay v10+ stores full Stripe objects here
    t.text :metadata
    t.timestamps
  end

  create_table :pay_charges, force: true do |t|
    t.references :customer, foreign_key: { to_table: :pay_customers }
    t.references :subscription, foreign_key: { to_table: :pay_subscriptions }
    t.string :processor_id
    t.integer :amount
    t.integer :amount_refunded
    t.string :currency
    t.json :data
    t.json :object  # Pay v10+ stores full Stripe objects here
    t.timestamps
  end
end

# Define minimal Pay models for testing
# (We define our own instead of using the real Pay gem to avoid Rails engine complexity)
module Pay
  class Customer < ActiveRecord::Base
    self.table_name = "pay_customers"
    has_many :subscriptions, class_name: "Pay::Subscription", foreign_key: :customer_id
    has_many :charges, class_name: "Pay::Charge", foreign_key: :customer_id

    scope :with_subscriptions, -> { joins(:subscriptions) }
  end

  class Subscription < ActiveRecord::Base
    self.table_name = "pay_subscriptions"
    belongs_to :customer, class_name: "Pay::Customer"
    has_many :charges, class_name: "Pay::Charge"

    scope :active, -> { where(status: "active") }
    scope :trialing, -> { where(status: "trialing") }
    scope :paused, -> { where(status: "paused") }
    scope :canceled, -> { where(status: "canceled") }
    scope :ended, -> { where(status: "ended") }
  end

  class Charge < ActiveRecord::Base
    self.table_name = "pay_charges"
    belongs_to :customer, class_name: "Pay::Customer"
    belongs_to :subscription, class_name: "Pay::Subscription", optional: true
  end
end

# Now require the profitable gem components (skip engine)
require_relative "../lib/profitable/version"
require_relative "../lib/profitable/error"
require_relative "../lib/profitable/mrr_calculator"
require_relative "../lib/profitable/numeric_result"
require_relative "../lib/profitable/json_helpers"

require "active_support/core_ext/numeric/conversions"

# Define the Profitable module (mirroring the real implementation in lib/profitable.rb)
# IMPORTANT: This must be kept in sync with lib/profitable.rb.
# We can't load lib/profitable.rb directly because `require "pay"` loads the full
# Pay engine which needs Rails. Instead we define minimal Pay models above and
# mirror the Profitable module here.
module Profitable
  # Subscription status constants (at module level so MrrCalculator can reference them)
  EXCLUDED_STATUSES = ['trialing', 'paused'].freeze
  CHURNED_STATUSES  = ['canceled', 'ended'].freeze

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

    def monthly_summary(months: 12)
      calculate_monthly_summary(months)
    end

    def daily_summary(days: 30)
      calculate_daily_summary(days)
    end

    def period_data(in_the_last: DEFAULT_PERIOD)
      calculate_period_data(in_the_last)
    end

    private

    # Helper to load subscriptions with processor info from customer
    def subscriptions_with_processor(scope = Pay::Subscription.all)
      scope
        .includes(:customer)
        .select('pay_subscriptions.*, pay_customers.processor as customer_processor')
        .joins(:customer)
    end

    def paid_charges
      # Pay gem v10+ stores charge data in `object` column, older versions used `data`
      # We check both columns for backwards compatibility using database-agnostic JSON extraction

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
      calculate_churn_rate_for_period(period.ago, Time.current)
    end

    def calculate_churned_customers(period = DEFAULT_PERIOD)
      calculate_churned_subscribers_in_period(period.ago, Time.current)
    end

    def calculate_churned_mrr(period = DEFAULT_PERIOD)
      calculate_churned_mrr_in_period(period.ago, Time.current)
    end

    def calculate_new_mrr(period = DEFAULT_PERIOD)
      calculate_new_mrr_in_period(period.ago, Time.current)
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
      calculate_new_subscribers_in_period(period.ago, Time.current)
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
      subscriptions_with_processor(
        Pay::Subscription
          .where('pay_subscriptions.created_at <= ?', date)
          .where('pay_subscriptions.ends_at IS NULL OR pay_subscriptions.ends_at > ?', date)
          .where('pay_subscriptions.pause_starts_at IS NULL OR pay_subscriptions.pause_starts_at > ?', date)
          .where.not(status: EXCLUDED_STATUSES)
      ).sum do |subscription|
        MrrCalculator.process_subscription(subscription)
      end
    end

    def calculate_period_data(period)
      period_start = period.ago
      period_end = Time.current

      new_customers_count = actual_customers.where(created_at: period_start..period_end).count
      churned_count = calculate_churned_subscribers_in_period(period_start, period_end)
      new_mrr_val = calculate_new_mrr_in_period(period_start, period_end)
      churned_mrr_val = calculate_churned_mrr_in_period(period_start, period_end)
      revenue_val = paid_charges.where(created_at: period_start..period_end).sum(:amount)

      # Churn rate (reuses churned_count)
      total_at_start = Pay::Subscription
        .where('pay_subscriptions.created_at < ?', period_start)
        .where('pay_subscriptions.ends_at IS NULL OR pay_subscriptions.ends_at > ?', period_start)
        .where.not(status: EXCLUDED_STATUSES)
        .distinct
        .count('customer_id')
      churn_rate = total_at_start > 0 ? (churned_count.to_f / total_at_start * 100).round(1) : 0

      {
        new_customers: NumericResult.new(new_customers_count, :integer),
        churned_customers: NumericResult.new(churned_count, :integer),
        churn: NumericResult.new(churn_rate, :percentage),
        new_mrr: NumericResult.new(new_mrr_val),
        churned_mrr: NumericResult.new(churned_mrr_val),
        mrr_growth: NumericResult.new(new_mrr_val - churned_mrr_val),
        revenue: NumericResult.new(revenue_val)
      }
    end

    # Batched: loads all data in 5 queries then groups by month in Ruby
    def calculate_monthly_summary(months_count)
      overall_start = (months_count - 1).months.ago.beginning_of_month
      overall_end = Time.current.end_of_month

      # Bulk load all data for the full range
      new_sub_records = Pay::Subscription
        .where(created_at: overall_start..overall_end)
        .where.not(status: EXCLUDED_STATUSES)
        .pluck(:customer_id, :created_at)

      churned_sub_records = Pay::Subscription
        .where(status: CHURNED_STATUSES)
        .where(ends_at: overall_start..overall_end)
        .pluck(:customer_id, :ends_at)

      new_mrr_subs = subscriptions_with_processor(
        Pay::Subscription
          .where(status: 'active')
          .where(created_at: overall_start..overall_end)
      ).to_a

      churned_mrr_subs = subscriptions_with_processor(
        Pay::Subscription
          .where(status: CHURNED_STATUSES)
          .where(ends_at: overall_start..overall_end)
      ).to_a

      churn_base_records = Pay::Subscription
        .where('pay_subscriptions.created_at < ?', overall_end)
        .where('pay_subscriptions.ends_at IS NULL OR pay_subscriptions.ends_at > ?', overall_start)
        .where.not(status: EXCLUDED_STATUSES)
        .pluck(:customer_id, :created_at, :ends_at)

      # Group by month in Ruby
      summary = []
      (months_count - 1).downto(0) do |months_ago|
        month_start = months_ago.months.ago.beginning_of_month
        month_end = month_start.end_of_month

        new_count = new_sub_records
          .select { |_, created_at| created_at >= month_start && created_at <= month_end }
          .map(&:first).uniq.count

        churned_count = churned_sub_records
          .select { |_, ends_at| ends_at >= month_start && ends_at <= month_end }
          .map(&:first).uniq.count

        new_mrr_amount = new_mrr_subs
          .select { |s| s.created_at >= month_start && s.created_at <= month_end }
          .sum { |s| MrrCalculator.process_subscription(s) }

        churned_mrr_amount = churned_mrr_subs
          .select { |s| s.ends_at >= month_start && s.ends_at <= month_end }
          .sum { |s| MrrCalculator.process_subscription(s) }

        total_at_start = churn_base_records
          .select { |_, created_at, ends_at| created_at < month_start && (ends_at.nil? || ends_at > month_start) }
          .map(&:first).uniq.count

        churn_rate = total_at_start > 0 ? (churned_count.to_f / total_at_start * 100).round(1) : 0

        summary << {
          month: month_start.strftime('%Y-%m'),
          month_date: month_start,
          new_subscribers: new_count,
          churned_subscribers: churned_count,
          net_subscribers: new_count - churned_count,
          new_mrr: new_mrr_amount,
          churned_mrr: churned_mrr_amount,
          net_mrr: new_mrr_amount - churned_mrr_amount,
          churn_rate: churn_rate
        }
      end

      summary
    end

    # Batched: loads all data in 2 queries then groups by day in Ruby
    def calculate_daily_summary(days_count)
      overall_start = (days_count - 1).days.ago.beginning_of_day
      overall_end = Time.current.end_of_day

      new_sub_records = Pay::Subscription
        .where(created_at: overall_start..overall_end)
        .where.not(status: EXCLUDED_STATUSES)
        .pluck(:customer_id, :created_at)

      churned_sub_records = Pay::Subscription
        .where(status: CHURNED_STATUSES)
        .where(ends_at: overall_start..overall_end)
        .pluck(:customer_id, :ends_at)

      summary = []
      (days_count - 1).downto(0) do |days_ago|
        day_start = days_ago.days.ago.beginning_of_day
        day_end = day_start.end_of_day

        new_count = new_sub_records
          .select { |_, created_at| created_at >= day_start && created_at <= day_end }
          .map(&:first).uniq.count

        churned_count = churned_sub_records
          .select { |_, ends_at| ends_at >= day_start && ends_at <= day_end }
          .map(&:first).uniq.count

        summary << {
          date: day_start.to_date,
          new_subscribers: new_count,
          churned_subscribers: churned_count
        }
      end

      summary
    end

    # Consolidated methods that work with any date range
    def calculate_new_subscribers_in_period(period_start, period_end)
      Pay::Customer.joins(:subscriptions)
                   .where(pay_subscriptions: { created_at: period_start..period_end })
                   .where.not(pay_subscriptions: { status: EXCLUDED_STATUSES })
                   .distinct
                   .count
    end

    def calculate_churned_subscribers_in_period(period_start, period_end)
      Pay::Subscription
        .where(status: CHURNED_STATUSES)
        .where(ends_at: period_start..period_end)
        .distinct
        .count('customer_id')
    end

    def calculate_new_mrr_in_period(period_start, period_end)
      subscriptions_with_processor(
        Pay::Subscription
          .where(status: 'active')
          .where(created_at: period_start..period_end)
      ).sum do |subscription|
        MrrCalculator.process_subscription(subscription)
      end
    end

    def calculate_churned_mrr_in_period(period_start, period_end)
      subscriptions_with_processor(
        Pay::Subscription
          .where(status: CHURNED_STATUSES)
          .where(ends_at: period_start..period_end)
      ).sum do |subscription|
        MrrCalculator.process_subscription(subscription)
      end
    end

    def calculate_churn_rate_for_period(period_start, period_end)
      # Count subscribers who were active AT the start of the period
      total_subscribers_start = Pay::Subscription
        .where('pay_subscriptions.created_at < ?', period_start)
        .where('pay_subscriptions.ends_at IS NULL OR pay_subscriptions.ends_at > ?', period_start)
        .where.not(status: EXCLUDED_STATUSES)
        .distinct
        .count('customer_id')

      churned = calculate_churned_subscribers_in_period(period_start, period_end)
      return 0 if total_subscribers_start == 0

      (churned.to_f / total_subscribers_start * 100).round(1)
    end

  end
end

# Test helper methods
module ProfitableTestHelpers
  # Creates a Stripe subscription with the v10+ object column structure
  def create_stripe_subscription_v10(customer:, unit_amount:, interval: "month", interval_count: 1, quantity: 1, status: "active", additional_items: [])
    items_data = [
      {
        "id" => "si_#{SecureRandom.hex(8)}",
        "quantity" => quantity,
        "price" => {
          "id" => "price_#{SecureRandom.hex(8)}",
          "unit_amount" => unit_amount,
          "recurring" => {
            "interval" => interval,
            "interval_count" => interval_count
          }
        }
      }
    ]

    additional_items.each do |item|
      items_data << {
        "id" => "si_#{SecureRandom.hex(8)}",
        "quantity" => item[:quantity] || 1,
        "price" => {
          "id" => "price_#{SecureRandom.hex(8)}",
          "unit_amount" => item[:unit_amount],
          "recurring" => {
            "interval" => item[:interval] || interval,
            "interval_count" => item[:interval_count] || interval_count
          }
        }
      }
    end

    Pay::Subscription.create!(
      customer: customer,
      processor_id: "sub_#{SecureRandom.hex(8)}",
      name: "default",
      quantity: quantity,
      status: status,
      data: nil,
      object: {
        "id" => "sub_#{SecureRandom.hex(8)}",
        "status" => status,
        "items" => {
          "data" => items_data
        }
      }
    )
  end

  # Creates a Stripe subscription with the legacy data column structure (pre-v10)
  def create_stripe_subscription_legacy(customer:, unit_amount:, interval: "month", interval_count: 1, quantity: 1, status: "active")
    Pay::Subscription.create!(
      customer: customer,
      processor_id: "sub_#{SecureRandom.hex(8)}",
      name: "default",
      quantity: quantity,
      status: status,
      object: nil,
      data: {
        "subscription_items" => [
          {
            "id" => "si_#{SecureRandom.hex(8)}",
            "quantity" => quantity,
            "unit_amount" => unit_amount,
            "price" => {
              "unit_amount" => unit_amount,
              "recurring" => {
                "interval" => interval,
                "interval_count" => interval_count
              }
            }
          }
        ]
      }
    )
  end

  # Creates a Braintree subscription
  def create_braintree_subscription(customer:, price:, interval: "month", interval_count: 1, quantity: 1, status: "active")
    Pay::Subscription.create!(
      customer: customer,
      processor_id: "sub_#{SecureRandom.hex(8)}",
      name: "default",
      quantity: quantity,
      status: status,
      object: {
        "price" => price,
        "billing_period_unit" => interval,
        "billing_period_frequency" => interval_count
      }
    )
  end

  # Creates a Paddle Billing subscription (v10+ structure)
  def create_paddle_billing_subscription(customer:, amount:, interval: "month", frequency: 1, quantity: 1, status: "active", additional_items: [])
    items_data = [
      {
        "quantity" => quantity,
        "price" => {
          "unit_price" => { "amount" => amount },
          "billing_cycle" => {
            "interval" => interval,
            "frequency" => frequency
          }
        }
      }
    ]

    additional_items.each do |item|
      items_data << {
        "quantity" => item[:quantity] || 1,
        "price" => {
          "unit_price" => { "amount" => item[:amount] },
          "billing_cycle" => {
            "interval" => item[:interval] || interval,
            "frequency" => item[:frequency] || frequency
          }
        }
      }
    end

    Pay::Subscription.create!(
      customer: customer,
      processor_id: "sub_#{SecureRandom.hex(8)}",
      name: "default",
      quantity: quantity,
      status: status,
      object: {
        "items" => items_data
      }
    )
  end

  # Creates a Paddle Classic subscription
  def create_paddle_classic_subscription(customer:, recurring_price:, interval: "month", quantity: 1, status: "active")
    Pay::Subscription.create!(
      customer: customer,
      processor_id: "sub_#{SecureRandom.hex(8)}",
      name: "default",
      quantity: quantity,
      status: status,
      object: {
        "recurring_price" => recurring_price,
        "recurring_interval" => interval
      }
    )
  end

  # Creates a Pay customer with a specified processor
  def create_customer(processor:)
    Pay::Customer.create!(
      owner_type: "User",
      owner_id: rand(1..10000),
      processor: processor,
      processor_id: "cus_#{SecureRandom.hex(8)}",
      default: true
    )
  end

  # Creates a successful charge
  def create_successful_charge(customer:, amount:, subscription: nil, created_at: Time.current)
    Pay::Charge.create!(
      customer: customer,
      subscription: subscription,
      processor_id: "ch_#{SecureRandom.hex(8)}",
      amount: amount,
      currency: "usd",
      created_at: created_at,
      object: {
        "paid" => true,
        "status" => "succeeded"
      }
    )
  end

  # Creates a charge with legacy data column
  def create_successful_charge_legacy(customer:, amount:, subscription: nil, created_at: Time.current)
    Pay::Charge.create!(
      customer: customer,
      subscription: subscription,
      processor_id: "ch_#{SecureRandom.hex(8)}",
      amount: amount,
      currency: "usd",
      created_at: created_at,
      object: nil,
      data: {
        "paid" => true,
        "status" => "succeeded"
      }
    )
  end

  # Creates a failed/refunded charge
  def create_failed_charge(customer:, amount:)
    Pay::Charge.create!(
      customer: customer,
      processor_id: "ch_#{SecureRandom.hex(8)}",
      amount: amount,
      currency: "usd",
      object: {
        "paid" => false,
        "status" => "failed"
      }
    )
  end
end

class Minitest::Test
  include ProfitableTestHelpers

  def setup
    # Clean up database before each test
    Pay::Charge.delete_all
    Pay::Subscription.delete_all
    Pay::Customer.delete_all
  end
end
