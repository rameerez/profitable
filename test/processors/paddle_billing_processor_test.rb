# frozen_string_literal: true

require "test_helper"

class ProcessorsPaddleBillingProcessorTest < Minitest::Test
  # ============================================================================
  # SETUP
  # ============================================================================

  def setup
    super
    @customer = create_customer(processor: "paddle_billing")
  end

  # ============================================================================
  # BASIC MRR CALCULATION
  # ============================================================================

  def test_calculates_mrr_for_monthly_subscription
    subscription = create_paddle_billing_subscription(
      customer: @customer,
      amount: 9900,  # $99/month
      interval: "month",
      frequency: 1
    )
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)

    assert_equal 9900, processor.calculate_mrr
  end

  def test_calculates_mrr_for_yearly_subscription
    subscription = create_paddle_billing_subscription(
      customer: @customer,
      amount: 118800,  # $1188/year = $99/month
      interval: "year",
      frequency: 1
    )
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)

    assert_equal 9900, processor.calculate_mrr
  end

  def test_calculates_mrr_for_quarterly_subscription
    subscription = create_paddle_billing_subscription(
      customer: @customer,
      amount: 29700,  # $297/quarter = $99/month
      interval: "month",
      frequency: 3
    )
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)

    assert_equal 9900, processor.calculate_mrr
  end

  def test_calculates_mrr_for_weekly_subscription
    subscription = create_paddle_billing_subscription(
      customer: @customer,
      amount: 2500,  # $25/week * 4 = $100/month
      interval: "week",
      frequency: 1
    )
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)

    assert_equal 10000, processor.calculate_mrr
  end

  # ============================================================================
  # QUANTITY HANDLING
  # ============================================================================

  def test_calculates_mrr_with_quantity
    subscription = create_paddle_billing_subscription(
      customer: @customer,
      amount: 1000,  # $10/month per seat
      interval: "month",
      quantity: 5  # 5 seats
    )
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)

    assert_equal 5000, processor.calculate_mrr  # $50/month
  end

  # ============================================================================
  # MULTI-ITEM SUBSCRIPTIONS (REGRESSION TESTS)
  # ============================================================================

  def test_calculates_mrr_for_multi_item_subscription
    # REGRESSION TEST: Ensure ALL items are summed, not just the first one
    subscription = create_paddle_billing_subscription(
      customer: @customer,
      amount: 5000,  # Base plan: $50/month
      interval: "month",
      additional_items: [
        { amount: 2000, quantity: 1 },  # Add-on 1: $20/month
        { amount: 1000, quantity: 3 }   # Add-on 2: $10/month * 3 = $30/month
      ]
    )
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)

    # Total: $50 + $20 + $30 = $100/month = 10000 cents
    assert_equal 10000, processor.calculate_mrr
  end

  def test_calculates_mrr_for_multi_item_with_different_intervals
    # Mix of monthly and yearly items
    subscription = create_paddle_billing_subscription(
      customer: @customer,
      amount: 5000,  # Base: $50/month
      interval: "month",
      additional_items: [
        { amount: 12000, interval: "year", frequency: 1, quantity: 1 }  # $120/year = $10/month
      ]
    )
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)

    # Total: $50 + $10 = $60/month = 6000 cents
    assert_equal 6000, processor.calculate_mrr
  end

  def test_calculates_mrr_for_subscription_with_many_items
    # Stress test with many items
    additional_items = 10.times.map do |i|
      { amount: 100 * (i + 1), quantity: 1 }  # $1, $2, $3... $10
    end

    subscription = create_paddle_billing_subscription(
      customer: @customer,
      amount: 1000,  # Base: $10
      interval: "month",
      additional_items: additional_items
    )
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)

    # Total: $10 + (1+2+3+4+5+6+7+8+9+10) = $10 + $55 = $65 = 6500 cents
    assert_equal 6500, processor.calculate_mrr
  end

  # ============================================================================
  # EDGE CASES AND ERROR HANDLING
  # ============================================================================

  def test_returns_zero_for_nil_subscription_data
    subscription = create_paddle_billing_subscription(
      customer: @customer,
      amount: 9900,
      interval: "month"
    )
    subscription.update!(object: nil, data: nil)
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)

    assert_equal 0, processor.calculate_mrr
  end

  def test_returns_zero_for_nil_items
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      status: "active",
      object: { "items" => nil }
    )
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)

    assert_equal 0, processor.calculate_mrr
  end

  def test_returns_zero_for_empty_items
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      status: "active",
      object: { "items" => [] }
    )
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)

    assert_equal 0, processor.calculate_mrr
  end

  def test_skips_items_with_nil_price_data
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      status: "active",
      object: {
        "items" => [
          { "quantity" => 1, "price" => nil },
          {
            "quantity" => 1,
            "price" => {
              "unit_price" => { "amount" => 3000 },
              "billing_cycle" => { "interval" => "month", "frequency" => 1 }
            }
          }
        ]
      }
    )
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)

    assert_equal 3000, processor.calculate_mrr
  end

  def test_skips_items_with_nil_amount
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      status: "active",
      object: {
        "items" => [
          {
            "quantity" => 1,
            "price" => {
              "unit_price" => { "amount" => nil },
              "billing_cycle" => { "interval" => "month", "frequency" => 1 }
            }
          },
          {
            "quantity" => 1,
            "price" => {
              "unit_price" => { "amount" => 5000 },
              "billing_cycle" => { "interval" => "month", "frequency" => 1 }
            }
          }
        ]
      }
    )
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)

    assert_equal 5000, processor.calculate_mrr
  end

  def test_handles_missing_quantity_defaults_to_one
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      status: "active",
      object: {
        "items" => [
          {
            # No quantity specified
            "price" => {
              "unit_price" => { "amount" => 5000 },
              "billing_cycle" => { "interval" => "month", "frequency" => 1 }
            }
          }
        ]
      }
    )
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)

    assert_equal 5000, processor.calculate_mrr
  end

  # ============================================================================
  # RETURN TYPE CONSISTENCY
  # ============================================================================

  def test_always_returns_integer
    subscription = create_paddle_billing_subscription(
      customer: @customer,
      amount: 10000,  # $100/year = $8.33/month = 833 cents
      interval: "year"
    )
    processor = Profitable::Processors::PaddleBillingProcessor.new(subscription)
    result = processor.calculate_mrr

    assert_kind_of Integer, result
  end
end
