# frozen_string_literal: true

require "test_helper"

class ProcessorsPaddleClassicProcessorTest < Minitest::Test
  # ============================================================================
  # SETUP
  # ============================================================================

  def setup
    super
    @customer = create_customer(processor: "paddle_classic")
  end

  # ============================================================================
  # BASIC MRR CALCULATION
  # ============================================================================

  def test_calculates_mrr_for_monthly_subscription
    subscription = create_paddle_classic_subscription(
      customer: @customer,
      recurring_price: 9900,  # $99/month
      interval: "month"
    )
    processor = Profitable::Processors::PaddleClassicProcessor.new(subscription)

    assert_equal 9900, processor.calculate_mrr
  end

  def test_calculates_mrr_for_yearly_subscription
    subscription = create_paddle_classic_subscription(
      customer: @customer,
      recurring_price: 118800,  # $1188/year = $99/month
      interval: "year"
    )
    processor = Profitable::Processors::PaddleClassicProcessor.new(subscription)

    assert_equal 9900, processor.calculate_mrr
  end

  def test_calculates_mrr_for_weekly_subscription
    subscription = create_paddle_classic_subscription(
      customer: @customer,
      recurring_price: 2500,  # $25/week * 4 = $100/month
      interval: "week"
    )
    processor = Profitable::Processors::PaddleClassicProcessor.new(subscription)

    assert_equal 10000, processor.calculate_mrr
  end

  def test_calculates_mrr_for_daily_subscription
    subscription = create_paddle_classic_subscription(
      customer: @customer,
      recurring_price: 1000,  # $10/day * 30 = $300/month
      interval: "day"
    )
    processor = Profitable::Processors::PaddleClassicProcessor.new(subscription)

    assert_equal 30000, processor.calculate_mrr
  end

  # ============================================================================
  # QUANTITY HANDLING
  # ============================================================================

  def test_calculates_mrr_with_quantity
    subscription = create_paddle_classic_subscription(
      customer: @customer,
      recurring_price: 1000,  # $10/month per seat
      interval: "month",
      quantity: 5  # 5 seats
    )
    processor = Profitable::Processors::PaddleClassicProcessor.new(subscription)

    assert_equal 5000, processor.calculate_mrr  # $50/month
  end

  def test_calculates_mrr_with_quantity_and_yearly_billing
    subscription = create_paddle_classic_subscription(
      customer: @customer,
      recurring_price: 12000,  # $120/year per seat = $10/month per seat
      interval: "year",
      quantity: 3  # 3 seats
    )
    processor = Profitable::Processors::PaddleClassicProcessor.new(subscription)

    assert_equal 3000, processor.calculate_mrr  # $30/month
  end

  # ============================================================================
  # EDGE CASES AND ERROR HANDLING
  # ============================================================================

  def test_returns_zero_for_nil_subscription_data
    subscription = create_paddle_classic_subscription(
      customer: @customer,
      recurring_price: 9900,
      interval: "month"
    )
    subscription.update!(object: nil, data: nil)
    processor = Profitable::Processors::PaddleClassicProcessor.new(subscription)

    assert_equal 0, processor.calculate_mrr
  end

  def test_returns_zero_for_nil_recurring_price
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      status: "active",
      object: {
        "recurring_price" => nil,
        "recurring_interval" => "month"
      }
    )
    processor = Profitable::Processors::PaddleClassicProcessor.new(subscription)

    assert_equal 0, processor.calculate_mrr
  end

  def test_handles_nil_quantity_defaults_to_one
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      quantity: nil,
      status: "active",
      object: {
        "recurring_price" => 5000,
        "recurring_interval" => "month"
      }
    )
    processor = Profitable::Processors::PaddleClassicProcessor.new(subscription)

    assert_equal 5000, processor.calculate_mrr
  end

  # ============================================================================
  # RETURN TYPE CONSISTENCY
  # ============================================================================

  def test_always_returns_integer
    subscription = create_paddle_classic_subscription(
      customer: @customer,
      recurring_price: 10000,  # $100/year = $8.33/month = 833 cents
      interval: "year"
    )
    processor = Profitable::Processors::PaddleClassicProcessor.new(subscription)
    result = processor.calculate_mrr

    assert_kind_of Integer, result
  end
end
