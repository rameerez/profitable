# frozen_string_literal: true

require "test_helper"

class ProcessorsStripeProcessorTest < Minitest::Test
  # ============================================================================
  # SETUP
  # ============================================================================

  def setup
    super
    @customer = create_customer(processor: "stripe")
  end

  # ============================================================================
  # BASIC MRR CALCULATION (Pay v10+ with object column)
  # ============================================================================

  def test_calculates_mrr_for_monthly_subscription
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,  # $99/month
      interval: "month",
      interval_count: 1
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    assert_equal 9900, processor.calculate_mrr
  end

  def test_calculates_mrr_for_yearly_subscription
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 118800,  # $1188/year = $99/month
      interval: "year",
      interval_count: 1
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    assert_equal 9900, processor.calculate_mrr
  end

  def test_calculates_mrr_for_quarterly_subscription
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 29700,  # $297/quarter = $99/month
      interval: "month",
      interval_count: 3
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    assert_equal 9900, processor.calculate_mrr
  end

  def test_calculates_mrr_for_weekly_subscription
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 2500,  # $25/week * 4 = $100/month
      interval: "week",
      interval_count: 1
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    assert_equal 10000, processor.calculate_mrr
  end

  # ============================================================================
  # QUANTITY HANDLING
  # ============================================================================

  def test_calculates_mrr_with_quantity
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 1000,  # $10/month per seat
      interval: "month",
      quantity: 5  # 5 seats
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    assert_equal 5000, processor.calculate_mrr  # $50/month
  end

  def test_calculates_mrr_with_quantity_and_yearly_billing
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 12000,  # $120/year per seat = $10/month per seat
      interval: "year",
      quantity: 3  # 3 seats
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    assert_equal 3000, processor.calculate_mrr  # $30/month
  end

  # ============================================================================
  # MULTI-ITEM SUBSCRIPTIONS (REGRESSION TESTS)
  # ============================================================================

  def test_calculates_mrr_for_multi_item_subscription
    # REGRESSION TEST: Ensure ALL items are summed, not just the first one
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 5000,  # Base plan: $50/month
      interval: "month",
      additional_items: [
        { unit_amount: 2000, quantity: 1 },  # Add-on 1: $20/month
        { unit_amount: 1000, quantity: 3 }   # Add-on 2: $10/month * 3 = $30/month
      ]
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    # Total: $50 + $20 + $30 = $100/month = 10000 cents
    assert_equal 10000, processor.calculate_mrr
  end

  def test_calculates_mrr_for_multi_item_with_different_intervals
    # Mix of monthly and yearly items
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 5000,  # Base: $50/month
      interval: "month",
      additional_items: [
        { unit_amount: 12000, interval: "year", quantity: 1 }  # $120/year = $10/month
      ]
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    # Total: $50 + $10 = $60/month = 6000 cents
    assert_equal 6000, processor.calculate_mrr
  end

  def test_calculates_mrr_for_subscription_with_many_items
    # Stress test with many items
    additional_items = 10.times.map do |i|
      { unit_amount: 100 * (i + 1), quantity: 1 }  # $1, $2, $3... $10
    end

    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 1000,  # Base: $10
      interval: "month",
      additional_items: additional_items
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    # Total: $10 + (1+2+3+4+5+6+7+8+9+10) = $10 + $55 = $65 = 6500 cents
    assert_equal 6500, processor.calculate_mrr
  end

  # ============================================================================
  # LEGACY DATA COLUMN SUPPORT (Pay pre-v10)
  # ============================================================================

  def test_calculates_mrr_for_legacy_subscription_data_column
    # REGRESSION TEST: Ensure backwards compatibility with data column
    subscription = create_stripe_subscription_legacy(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    assert_equal 9900, processor.calculate_mrr
  end

  def test_calculates_mrr_for_legacy_yearly_subscription
    subscription = create_stripe_subscription_legacy(
      customer: @customer,
      unit_amount: 118800,  # $1188/year
      interval: "year"
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    assert_equal 9900, processor.calculate_mrr
  end

  # ============================================================================
  # EDGE CASES AND ERROR HANDLING
  # ============================================================================

  def test_returns_zero_for_nil_subscription_data
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )
    subscription.update!(object: nil, data: nil)
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    assert_equal 0, processor.calculate_mrr
  end

  def test_returns_zero_for_empty_subscription_items
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      status: "active",
      object: {
        "items" => { "data" => [] }
      }
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    assert_equal 0, processor.calculate_mrr
  end

  def test_returns_zero_for_nil_subscription_items
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      status: "active",
      object: {
        "items" => { "data" => nil }
      }
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    assert_equal 0, processor.calculate_mrr
  end

  def test_skips_items_with_nil_unit_amount
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      status: "active",
      object: {
        "items" => {
          "data" => [
            {
              "quantity" => 1,
              "price" => {
                "unit_amount" => nil,
                "recurring" => { "interval" => "month", "interval_count" => 1 }
              }
            },
            {
              "quantity" => 1,
              "price" => {
                "unit_amount" => 5000,
                "recurring" => { "interval" => "month", "interval_count" => 1 }
              }
            }
          ]
        }
      }
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    # Should only count the valid item: $50
    assert_equal 5000, processor.calculate_mrr
  end

  def test_skips_items_with_nil_price_data
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      status: "active",
      object: {
        "items" => {
          "data" => [
            { "quantity" => 1, "price" => nil },
            {
              "quantity" => 1,
              "price" => {
                "unit_amount" => 3000,
                "recurring" => { "interval" => "month", "interval_count" => 1 }
              }
            }
          ]
        }
      }
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    assert_equal 3000, processor.calculate_mrr
  end

  def test_handles_missing_quantity_defaults_to_one
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      status: "active",
      object: {
        "items" => {
          "data" => [
            {
              # No quantity specified
              "price" => {
                "unit_amount" => 5000,
                "recurring" => { "interval" => "month", "interval_count" => 1 }
              }
            }
          ]
        }
      }
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    assert_equal 5000, processor.calculate_mrr
  end

  def test_handles_missing_interval_count_defaults_to_one
    subscription = Pay::Subscription.create!(
      customer: @customer,
      processor_id: "sub_test",
      name: "default",
      status: "active",
      object: {
        "items" => {
          "data" => [
            {
              "quantity" => 1,
              "price" => {
                "unit_amount" => 5000,
                "recurring" => { "interval" => "month" }  # No interval_count
              }
            }
          ]
        }
      }
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)

    assert_equal 5000, processor.calculate_mrr
  end

  # ============================================================================
  # RETURN TYPE CONSISTENCY
  # ============================================================================

  def test_always_returns_integer
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,  # $100/year = $8.33/month = 833 cents
      interval: "year"
    )
    processor = Profitable::Processors::StripeProcessor.new(subscription)
    result = processor.calculate_mrr

    assert_kind_of Integer, result
  end
end
