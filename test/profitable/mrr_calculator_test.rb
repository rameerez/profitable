# frozen_string_literal: true
require "test_helper"

class MrrCalculatorTest < Minitest::Test
  def setup
    super
    @logger_io = StringIO.new
    Rails.logger = Logger.new(@logger_io)
  end

  def teardown
    Rails.logger = Logger.new($stdout)
    super
  end

  def create_subscription(processor:, amount_cents:, interval: "month", interval_count: 1, status: "active", quantity: 1)
    customer = Pay::Customer.create!(processor: processor)
    data = case processor
           when "stripe"
             { "subscription_items" => [{ "price" => { "unit_amount" => amount_cents, "recurring" => { "interval" => interval, "interval_count" => interval_count } } }] }
           when "braintree"
             { "price" => amount_cents, "billing_period_unit" => interval, "billing_period_frequency" => interval_count }
           when "paddle_billing"
             { "items" => [{ "price" => { "unit_price" => { "amount" => amount_cents }, "billing_cycle" => { "interval" => interval, "frequency" => interval_count } } }] }
           else
             { "recurring_price" => amount_cents, "recurring_interval" => interval }
           end

    Pay::Subscription.create!(
      customer: customer,
      processor: processor,
      status: status,
      quantity: quantity,
      current_period_start: Time.now - 15.days,
      current_period_end: Time.now + 15.days,
      data: data
    )
  end

  def test_calculate_sums_positive_mrr_only
    create_subscription(processor: "stripe", amount_cents: 1000)
    create_subscription(processor: "stripe", amount_cents: 0)
    # paused and trialing are excluded
    create_subscription(processor: "stripe", amount_cents: 500, status: "paused")
    create_subscription(processor: "stripe", amount_cents: 500, status: "trialing")

    total = Profitable::MrrCalculator.calculate
    assert_equal 1000, total
  end

  def test_process_subscription_handles_nil
    assert_equal 0, Profitable::MrrCalculator.process_subscription(nil)
  end

  def test_process_subscription_handles_nil_data
    sub = create_subscription(processor: "stripe", amount_cents: 1000)
    sub.update!(data: nil)
    assert_equal 0, Profitable::MrrCalculator.process_subscription(sub)
  end

  def test_calculate_error_raises_profitable_error
    Pay::Subscription.stub(:active, -> { raise "boom" }) do
      assert_raises(Profitable::Error) { Profitable::MrrCalculator.calculate }
      assert_match /Error calculating total MRR/, @logger_io.string
    end
  end

  def test_process_subscription_error_returns_zero
    sub = create_subscription(processor: "stripe", amount_cents: 1000)
    Profitable::MrrCalculator.stub(:processor_for, ->(_) { raise "oops" }) do
      assert_equal 0, Profitable::MrrCalculator.process_subscription(sub)
      assert_match /Error calculating MRR for subscription/, @logger_io.string
    end
  end
end