# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# SimpleCov must be loaded BEFORE any application code
# Configuration is auto-loaded from .simplecov file
require "simplecov"

require "bundler/setup"
require "active_record"
require "active_support/all"
require "active_support/testing/time_helpers"
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

# Now require the profitable gem components.
# We intentionally load the shared metrics implementation directly instead of
# mirroring the Profitable module in tests. This keeps the standalone test
# harness exercising the real production code paths.
require_relative "../lib/profitable/version"
require_relative "../lib/profitable/error"
require_relative "../lib/profitable/mrr_calculator"
require_relative "../lib/profitable/numeric_result"
require_relative "../lib/profitable/json_helpers"
require_relative "../lib/profitable/metrics"

require "active_support/core_ext/numeric/conversions"

# Test helper methods
module ProfitableTestHelpers
  # Creates a Stripe subscription with the v10+ object column structure
  def create_stripe_subscription_v10(customer:, unit_amount:, interval: "month", interval_count: 1, quantity: 1, status: "active", usage_type: nil, additional_items: [])
    items_data = [
      {
        "id" => "si_#{SecureRandom.hex(8)}",
        "quantity" => quantity,
        "price" => {
          "id" => "price_#{SecureRandom.hex(8)}",
          "unit_amount" => unit_amount,
          "recurring" => {
            "interval" => interval,
            "interval_count" => interval_count,
            "usage_type" => usage_type
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
            "interval_count" => item[:interval_count] || interval_count,
            "usage_type" => item[:usage_type]
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
  def create_successful_charge(customer:, amount:, subscription: nil, created_at: Time.current, amount_refunded: 0)
    Pay::Charge.create!(
      customer: customer,
      subscription: subscription,
      processor_id: "ch_#{SecureRandom.hex(8)}",
      amount: amount,
      amount_refunded: amount_refunded,
      currency: "usd",
      created_at: created_at,
      object: {
        "paid" => true,
        "status" => "succeeded"
      }
    )
  end

  # Creates a charge with legacy data column
  def create_successful_charge_legacy(customer:, amount:, subscription: nil, created_at: Time.current, amount_refunded: 0)
    Pay::Charge.create!(
      customer: customer,
      subscription: subscription,
      processor_id: "ch_#{SecureRandom.hex(8)}",
      amount: amount,
      amount_refunded: amount_refunded,
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
  include ActiveSupport::Testing::TimeHelpers

  def setup
    # Clean up database before each test
    Pay::Charge.delete_all
    Pay::Subscription.delete_all
    Pay::Customer.delete_all
  end

  def teardown
    travel_back
  end
end
