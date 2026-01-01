# frozen_string_literal: true

require "test_helper"

class ProcessorsBraintreeProcessorTest < Minitest::Test
  # ============================================================================
  # SETUP
  # ============================================================================

  def setup
    super
    @customer = create_customer(processor: "braintree")
  end

  # ============================================================================
  # BASIC MRR CALCULATION
  # ============================================================================

  def test_calculates_mrr_for_monthly_subscription
    subscription = create_braintree_subscription(
      customer: @customer,
      price: 9900,  # $99/month
      interval: "month",
      interval_count: 1
    )
    processor = Profitable::Processors::BraintreeProcessor.new(subscription)

    assert_equal 9900, processor.calculate_mrr
  end

  def test_calculates_mrr_for_yearly_subscription
    subscription = create_braintree_subscription(
      customer: @customer,
      price: 118800,  # $1188/year = $99/month
      interval: "year",
      interval_count: 1
    )
    processor = Profitable::Processors::BraintreeProcessor.new(subscription)

    assert_equal 9900, processor.calculate_mrr
  end

  def test_calculates_mrr_for_quarterly_subscription
    subscription = create_braintree_subscription(
      customer: @customer,
      price: 29700,  # $297/quarter = $99/month
      interval: "month",
      interval_count: 3
    )
    processor = Profitable::Processors::BraintreeProcessor.new(subscription)

    assert_equal 9900, processor.calculate_mrr
  end

  def test_calculates_mrr_for_weekly_subscription
    subscription = create_braintree_subscription(
      customer: @customer,
      price: 2500,  # $25/week * 4 = $100/month
      interval: "week",
      interval_count: 1
    )
    processor = Profitable::Processors::BraintreeProcessor.new(subscription)

    assert_equal 10000, processor.calculate_mrr
  end

  def test_calculates_mrr_for_daily_subscription
    subscription = create_braintree_subscription(
      customer: @customer,
      price: 1000,  # $10/day * 30 = $300/month
      interval: "day",
      interval_count: 1
    )
    processor = Profitable::Processors::BraintreeProcessor.new(subscription)

    assert_equal 30000, processor.calculate_mrr
  end

  # ============================================================================
  # QUANTITY HANDLING
  # ============================================================================

  def test_calculates_mrr_with_quantity
    subscription = create_braintree_subscription(
      customer: @customer,
      price: 1000,  # $10/month per seat
      interval: "month",
      quantity: 10  # 10 seats
    )
    processor = Profitable::Processors::BraintreeProcessor.new(subscription)

    assert_equal 10000, processor.calculate_mrr  # $100/month
  end

  def test_calculates_mrr_with_quantity_and_yearly_billing
    subscription = create_braintree_subscription(
      customer: @customer,
      price: 12000,  # $120/year per seat = $10/month per seat
      interval: "year",
      quantity: 5  # 5 seats
    )
    processor = Profitable::Processors::BraintreeProcessor.new(subscription)

    assert_equal 5000, processor.calculate_mrr  # $50/month
  end

  # ============================================================================
  # EDGE CASES AND ERROR HANDLING
  # ============================================================================

  def test_returns_zero_for_nil_subscription_data
    subscription = create_braintree_subscription(
      customer: @customer,
      price: 9900,
      interval: "month"
    )
    subscription.update!(object: nil, data: nil)
    processor = Profitable::Processors::BraintreeProcessor.new(subscription)

    assert_equal 0, processor.calculate_mrr
  end

  def test_returns_zero_for_nil_price
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      status: "active",
      object: {
        "price" => nil,
        "billing_period_unit" => "month",
        "billing_period_frequency" => 1
      }
    )
    processor = Profitable::Processors::BraintreeProcessor.new(subscription)

    assert_equal 0, processor.calculate_mrr
  end

  def test_handles_missing_billing_period_frequency_defaults_to_one
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      quantity: 1,
      status: "active",
      object: {
        "price" => 5000,
        "billing_period_unit" => "month"
        # No billing_period_frequency
      }
    )
    processor = Profitable::Processors::BraintreeProcessor.new(subscription)

    assert_equal 5000, processor.calculate_mrr
  end

  def test_handles_missing_quantity_uses_subscription_quantity
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      quantity: 3,  # Subscription-level quantity
      status: "active",
      object: {
        "price" => 1000,
        "billing_period_unit" => "month",
        "billing_period_frequency" => 1
      }
    )
    processor = Profitable::Processors::BraintreeProcessor.new(subscription)

    assert_equal 3000, processor.calculate_mrr
  end

  def test_handles_nil_quantity_defaults_to_one
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      quantity: nil,  # No quantity
      status: "active",
      object: {
        "price" => 5000,
        "billing_period_unit" => "month",
        "billing_period_frequency" => 1
      }
    )
    processor = Profitable::Processors::BraintreeProcessor.new(subscription)

    assert_equal 5000, processor.calculate_mrr
  end

  # ============================================================================
  # RETURN TYPE CONSISTENCY
  # ============================================================================

  def test_always_returns_integer
    subscription = create_braintree_subscription(
      customer: @customer,
      price: 10000,  # $100/year = $8.33/month = 833 cents
      interval: "year"
    )
    processor = Profitable::Processors::BraintreeProcessor.new(subscription)
    result = processor.calculate_mrr

    assert_kind_of Integer, result
  end
end
