# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/test/"
  enable_coverage :branch
end

require "bundler/setup"
require "minitest/autorun"
require "minitest/reporters"
Minitest::Reporters.use!(Minitest::Reporters::SpecReporter.new)

require "active_record"
require "action_controller/railtie"
require "rails"
require "database_cleaner/active_record"
require "timecop"

# Define a minimal Rails app for the engine
class TestApp < Rails::Application
  config.root = File.expand_path("..", __dir__)
  config.eager_load = false
  config.logger = Logger.new($stdout)
  config.log_level = :warn
  config.secret_key_base = "test-key-base"
  config.hosts << "example.org"
  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = false
end

# Define ApplicationController so engine controllers can inherit from it
class ApplicationController < ActionController::Base; end

# Initialize the Rails app
Rails.application.initialize!

# Initialize database
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Schema.define do
  create_table :pay_customers, force: true do |t|
    t.string :processor
    t.string :processor_id
    t.integer :owner_id
    t.string :owner_type
    t.timestamps
  end

  create_table :pay_subscriptions, force: true do |t|
    t.integer :customer_id
    t.string :name
    t.string :processor
    t.string :processor_id
    t.string :status
    t.integer :quantity
    t.datetime :trial_ends_at
    t.datetime :ends_at
    t.datetime :current_period_start
    t.datetime :current_period_end
    t.json :data
    t.timestamps
  end

  create_table :pay_charges, force: true do |t|
    t.integer :customer_id
    t.integer :subscription_id
    t.string :processor
    t.string :processor_id
    t.integer :amount
    t.integer :amount_refunded
    t.string :currency
    t.json :data
    t.datetime :created_at
    t.datetime :updated_at
  end
end

# Minimal models to satisfy queries in the gem
module Pay
  class Customer < ActiveRecord::Base
    self.table_name = "pay_customers"
    has_many :subscriptions, class_name: "Pay::Subscription", foreign_key: :customer_id
    has_many :charges, class_name: "Pay::Charge", foreign_key: :customer_id
  end

  class Subscription < ActiveRecord::Base
    self.table_name = "pay_subscriptions"
    belongs_to :customer, class_name: "Pay::Customer"

    scope :active, -> { where(status: "active") }

    # Mirror attribute selected in queries: pay_customers.processor as customer_processor
    def customer_processor
      customer&.processor
    end
  end

  class Charge < ActiveRecord::Base
    self.table_name = "pay_charges"
    belongs_to :customer, class_name: "Pay::Customer"
    belongs_to :subscription, class_name: "Pay::Subscription", optional: true
  end

  # Stubs for Pay processors to avoid NameError during Pay engine initialization
  module Stripe
    def self.enabled? = false
    def self.configure_webhooks; end
  end
  module Braintree
    def self.enabled? = false
    def self.configure_webhooks; end
  end
  module Paddle
    def self.enabled? = false
    def self.configure_webhooks; end
  end
  module PaddleBilling
    def self.enabled? = false
    def self.configure_webhooks; end
  end
  module PaddleClassic
    def self.enabled? = false
    def self.configure_webhooks; end
  end
  module LemonSqueezy
    def self.enabled? = false
    def self.configure_webhooks; end
  end
end

# Load the gem under test
require "profitable"

# SQLite compatibility: emulate JSON operator queries using json_extract
if ActiveRecord::Base.connection.adapter_name =~ /SQLite/i
  module Profitable
    class << self
      private

      def paid_charges
        Pay::Charge
          .where("(json_extract(pay_charges.data, '$.paid') IS NULL OR json_extract(pay_charges.data, '$.paid') != ?) AND pay_charges.amount > 0", 'false')
          .where("json_extract(pay_charges.data, '$.status') = ? OR json_extract(pay_charges.data, '$.status') IS NULL", 'succeeded')
      end
    end
  end
end

# Configure DatabaseCleaner
DatabaseCleaner.strategy = :transaction
Minitest.after_run { DatabaseCleaner.clean_with(:truncation) }

class Minitest::Test
  def setup
    DatabaseCleaner.start
    Timecop.return
  end

  def teardown
    DatabaseCleaner.clean
  end
end