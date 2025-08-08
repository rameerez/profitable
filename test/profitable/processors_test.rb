# frozen_string_literal: true
require "test_helper"

class ProcessorsTest < Minitest::Test
  def build_subscription(processor:, data:, quantity: 1)
    customer = Pay::Customer.create!(processor: processor)
    Pay::Subscription.create!(
      customer: customer,
      processor: processor,
      status: "active",
      quantity: quantity,
      current_period_start: Time.now - 15.days,
      current_period_end: Time.now + 15.days,
      data: data
    )
  end

  def test_stripe_processor_monthly
    data = {
      "subscription_items" => [
        { "price" => { "unit_amount" => 1200, "recurring" => { "interval" => "month", "interval_count" => 1 } } }
      ]
    }
    sub = build_subscription(processor: "stripe", data: data)
    mrr = Profitable::MrrCalculator.process_subscription(sub)
    assert_equal 1200, mrr
  end

  def test_stripe_processor_yearly_quantity
    data = {
      "subscription_items" => [
        { "price" => { "unit_amount" => 2400, "recurring" => { "interval" => "year", "interval_count" => 1 } } }
      ]
    }
    sub = build_subscription(processor: "stripe", data: data, quantity: 3)
    mrr = Profitable::MrrCalculator.process_subscription(sub)
    assert_in_delta 600.0, mrr, 0.001
  end

  def test_braintree_processor_weekly
    data = {
      "price" => 500,
      "billing_period_unit" => "week",
      "billing_period_frequency" => 1
    }
    sub = build_subscription(processor: "braintree", data: data)
    mrr = Profitable::MrrCalculator.process_subscription(sub)
    assert_in_delta 2000.0, mrr, 0.001
  end

  def test_paddle_billing_processor_daily
    data = {
      "items" => [
        { "price" => { "unit_price" => { "amount" => 100 }, "billing_cycle" => { "interval" => "day", "frequency" => 2 } } }
      ]
    }
    sub = build_subscription(processor: "paddle_billing", data: data)
    mrr = Profitable::MrrCalculator.process_subscription(sub)
    assert_in_delta 1500.0, mrr, 0.001
  end

  def test_paddle_classic_processor_monthly
    data = { "recurring_price" => 999, "recurring_interval" => "month" }
    sub = build_subscription(processor: "paddle_classic", data: data)
    mrr = Profitable::MrrCalculator.process_subscription(sub)
    assert_equal 999, mrr
  end

  def test_base_normalize_unknown_interval_logs_and_returns_zero
    # capture logs
    io = StringIO.new
    logger = Logger.new(io)
    Rails.logger = logger
    base = Profitable::Processors::Base.new(nil)
    result = base.send(:normalize_to_monthly, 1000, "unknown", 1)
    assert_equal 0, result
    assert_match /Unknown interval/, io.string
  ensure
    Rails.logger = Logger.new($stdout)
  end

  def test_unknown_processor_falls_back_to_base
    io = StringIO.new
    Rails.logger = Logger.new(io)
    klass = Profitable::MrrCalculator.processor_for("notreal")
    assert_equal Profitable::Processors::Base, klass
    assert_match /Unknown processor/, io.string
  ensure
    Rails.logger = Logger.new($stdout)
  end
end