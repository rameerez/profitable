# frozen_string_literal: true

require "test_helper"

class MrrCalculatorTest < Minitest::Test
  # ============================================================================
  # SETUP
  # ============================================================================

  def setup
    super
    @stripe_customer = create_customer(processor: "stripe")
    @braintree_customer = create_customer(processor: "braintree")
    @paddle_billing_customer = create_customer(processor: "paddle_billing")
    @paddle_classic_customer = create_customer(processor: "paddle_classic")
  end

  # ============================================================================
  # CALCULATE: BASIC SCENARIOS
  # ============================================================================

  def test_calculate_returns_zero_when_no_subscriptions
    assert_equal 0, Profitable::MrrCalculator.calculate
  end

  def test_calculate_returns_mrr_for_single_subscription
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,  # $99/month
      interval: "month"
    )

    assert_equal 9900, Profitable::MrrCalculator.calculate
  end

  def test_calculate_returns_sum_of_all_subscriptions
    # Two $99/month subscriptions
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month"
    )
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 4900,  # $49/month
      interval: "month"
    )

    assert_equal 14800, Profitable::MrrCalculator.calculate  # $148/month
  end

  def test_calculate_sums_across_different_processors
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 5000,
      interval: "month"
    )
    create_braintree_subscription(
      customer: @braintree_customer,
      price: 3000,
      interval: "month"
    )
    create_paddle_billing_subscription(
      customer: @paddle_billing_customer,
      amount: 2000,
      interval: "month"
    )

    assert_equal 10000, Profitable::MrrCalculator.calculate  # $100/month
  end

  # ============================================================================
  # CALCULATE: FILTERS (status, trialing, paused)
  # ============================================================================

  def test_calculate_excludes_trialing_subscriptions
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month",
      status: "trialing"
    )

    assert_equal 0, Profitable::MrrCalculator.calculate
  end

  def test_calculate_excludes_on_trial_subscriptions
    subscription = create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month",
      status: "on_trial"
    )
    subscription.update!(trial_ends_at: 5.days.from_now)

    assert_equal 0, Profitable::MrrCalculator.calculate
  end

  def test_calculate_excludes_active_subscriptions_still_on_trial
    subscription = create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )
    subscription.update!(trial_ends_at: 5.days.from_now)

    assert_equal 0, Profitable::MrrCalculator.calculate
  end

  def test_calculate_excludes_paused_subscriptions
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month",
      status: "paused"
    )

    assert_equal 0, Profitable::MrrCalculator.calculate
  end

  def test_calculate_excludes_incomplete_unpaid_and_incomplete_expired_subscriptions
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month",
      status: "incomplete"
    )
    create_stripe_subscription_v10(
      customer: create_customer(processor: "stripe"),
      unit_amount: 4900,
      interval: "month",
      status: "unpaid"
    )
    create_stripe_subscription_v10(
      customer: create_customer(processor: "stripe"),
      unit_amount: 2900,
      interval: "month",
      status: "incomplete_expired"
    )

    assert_equal 0, Profitable::MrrCalculator.calculate
  end

  def test_calculate_excludes_canceled_subscriptions
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month",
      status: "canceled"
    )

    assert_equal 0, Profitable::MrrCalculator.calculate
  end

  def test_calculate_excludes_ended_subscriptions
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month",
      status: "ended"
    )

    assert_equal 0, Profitable::MrrCalculator.calculate
  end

  def test_calculate_includes_past_due_subscriptions
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month",
      status: "past_due"
    )

    assert_equal 9900, Profitable::MrrCalculator.calculate
  end

  def test_calculate_includes_canceled_subscription_still_in_grace_period
    subscription = create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month",
      status: "canceled"
    )
    subscription.update!(ends_at: 5.days.from_now)

    assert_equal 9900, Profitable::MrrCalculator.calculate
  end

  def test_calculate_includes_cancelled_subscription_still_in_grace_period
    subscription = create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month",
      status: "cancelled"
    )
    subscription.update!(ends_at: 5.days.from_now)

    assert_equal 9900, Profitable::MrrCalculator.calculate
  end

  def test_calculate_includes_active_subscriptions_until_future_pause_or_end_date
    pausing_subscription = create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 5000,
      interval: "month",
      status: "active"
    )
    pausing_subscription.update!(pause_starts_at: 5.days.from_now)

    ending_subscription = create_stripe_subscription_v10(
      customer: create_customer(processor: "stripe"),
      unit_amount: 3000,
      interval: "month",
      status: "active"
    )
    ending_subscription.update!(ends_at: 5.days.from_now)

    assert_equal 8000, Profitable::MrrCalculator.calculate
  end

  def test_calculate_includes_only_active_subscriptions
    # Active: $50
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 5000,
      interval: "month",
      status: "active"
    )

    # Trialing: $30 (should be excluded)
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 3000,
      interval: "month",
      status: "trialing"
    )

    # Canceled: $20 (should be excluded)
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 2000,
      interval: "month",
      status: "canceled"
    )

    assert_equal 5000, Profitable::MrrCalculator.calculate
  end

  # ============================================================================
  # PROCESS_SUBSCRIPTION: PROCESSOR ROUTING
  # ============================================================================

  def test_process_subscription_routes_to_stripe_processor
    subscription = create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month"
    )

    assert_equal 9900, Profitable::MrrCalculator.process_subscription(subscription)
  end

  def test_process_subscription_ignores_metered_stripe_items
    subscription = create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 5000,
      interval: "month",
      usage_type: "metered"
    )

    assert_equal 0, Profitable::MrrCalculator.process_subscription(subscription)
  end

  def test_process_subscription_ignores_metered_items_but_keeps_licensed_items
    subscription = create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 5000,
      interval: "month",
      additional_items: [
        { unit_amount: 2000, interval: "month", usage_type: "metered" }
      ]
    )

    assert_equal 5000, Profitable::MrrCalculator.process_subscription(subscription)
  end

  def test_process_subscription_routes_to_braintree_processor
    subscription = create_braintree_subscription(
      customer: @braintree_customer,
      price: 4900,
      interval: "month"
    )

    assert_equal 4900, Profitable::MrrCalculator.process_subscription(subscription)
  end

  def test_process_subscription_handles_braintree_string_amounts
    subscription = create_braintree_subscription(
      customer: @braintree_customer,
      price: "4900",
      interval: "month",
      quantity: 2
    )

    assert_equal 9800, Profitable::MrrCalculator.process_subscription(subscription)
  end

  def test_process_subscription_routes_to_paddle_billing_processor
    subscription = create_paddle_billing_subscription(
      customer: @paddle_billing_customer,
      amount: 2900,
      interval: "month"
    )

    assert_equal 2900, Profitable::MrrCalculator.process_subscription(subscription)
  end

  def test_process_subscription_handles_paddle_billing_string_amounts
    subscription = create_paddle_billing_subscription(
      customer: @paddle_billing_customer,
      amount: "2900",
      interval: "month",
      quantity: 2
    )

    assert_equal 5800, Profitable::MrrCalculator.process_subscription(subscription)
  end

  def test_process_subscription_routes_to_paddle_classic_processor
    subscription = create_paddle_classic_subscription(
      customer: @paddle_classic_customer,
      recurring_price: 1900,
      interval: "month"
    )

    assert_equal 1900, Profitable::MrrCalculator.process_subscription(subscription)
  end

  def test_process_subscription_handles_paddle_classic_string_amounts
    subscription = create_paddle_classic_subscription(
      customer: @paddle_classic_customer,
      recurring_price: "1900",
      interval: "month",
      quantity: 3
    )

    assert_equal 5700, Profitable::MrrCalculator.process_subscription(subscription)
  end

  def test_process_subscription_uses_base_processor_for_unknown_processor
    unknown_customer = create_customer(processor: "unknown_processor")
    subscription = Pay::Subscription.create!(
      customer: unknown_customer,
      processor_id: "sub_test",
      name: "default",
      status: "active",
      object: { "price" => 9900 }
    )

    # Base processor returns 0
    assert_equal 0, Profitable::MrrCalculator.process_subscription(subscription)
  end

  # ============================================================================
  # PROCESS_SUBSCRIPTION: ERROR HANDLING
  # ============================================================================

  def test_process_subscription_returns_zero_for_nil_subscription
    assert_equal 0, Profitable::MrrCalculator.process_subscription(nil)
  end

  def test_process_subscription_returns_zero_for_nil_data
    subscription = create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month"
    )
    subscription.update!(object: nil, data: nil)

    assert_equal 0, Profitable::MrrCalculator.process_subscription(subscription)
  end

  def test_process_subscription_returns_zero_for_negative_mrr
    # This shouldn't happen in practice, but we guard against it
    subscription = create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month"
    )

    # Stub the processor to return a negative value
    Profitable::Processors::StripeProcessor.any_instance.stubs(:calculate_mrr).returns(-1000)

    assert_equal 0, Profitable::MrrCalculator.process_subscription(subscription)
  end

  def test_process_subscription_handles_exceptions_gracefully
    subscription = create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month"
    )

    # Stub the processor to raise an error
    Profitable::Processors::StripeProcessor.any_instance.stubs(:calculate_mrr).raises(StandardError.new("Test error"))

    # Should return 0 instead of crashing
    assert_equal 0, Profitable::MrrCalculator.process_subscription(subscription)
  end

  def test_calculate_wraps_unexpected_errors_in_profitable_error
    Profitable.stubs(:calculate_mrr_at).raises(StandardError.new("database exploded"))

    error = assert_raises(Profitable::Error) { Profitable::MrrCalculator.calculate }

    assert_includes error.message, "database exploded"
  end

  def test_calculate_matches_the_mrr_at_snapshot_for_now
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month"
    )
    create_braintree_subscription(
      customer: @braintree_customer,
      price: 3000,
      interval: "month"
    )

    # Current MRR and the MRR-at-date snapshot must be the same query;
    # if these ever diverge, growth rates stop being trustworthy.
    assert_equal Profitable.send(:calculate_mrr_at, Time.current), Profitable::MrrCalculator.calculate
  end

  # ============================================================================
  # SUBSCRIPTION_DATA: BACKWARDS COMPATIBILITY
  # ============================================================================

  def test_subscription_data_returns_object_when_present
    subscription = create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month"
    )

    data = Profitable::MrrCalculator.subscription_data(subscription)

    assert_equal subscription.object, data
  end

  def test_subscription_data_returns_data_when_object_is_nil
    subscription = create_stripe_subscription_legacy(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month"
    )

    data = Profitable::MrrCalculator.subscription_data(subscription)

    assert_equal subscription.data, data
  end

  def test_subscription_data_returns_nil_when_both_nil
    subscription = create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month"
    )
    subscription.update!(object: nil, data: nil)

    data = Profitable::MrrCalculator.subscription_data(subscription)

    assert_nil data
  end

  # ============================================================================
  # PROCESSOR_FOR: PROCESSOR CLASS SELECTION
  # ============================================================================

  def test_processor_for_returns_stripe_processor
    assert_equal Profitable::Processors::StripeProcessor,
                 Profitable::MrrCalculator.processor_for("stripe")
  end

  def test_processor_for_returns_braintree_processor
    assert_equal Profitable::Processors::BraintreeProcessor,
                 Profitable::MrrCalculator.processor_for("braintree")
  end

  def test_processor_for_returns_paddle_billing_processor
    assert_equal Profitable::Processors::PaddleBillingProcessor,
                 Profitable::MrrCalculator.processor_for("paddle_billing")
  end

  def test_processor_for_returns_paddle_classic_processor
    assert_equal Profitable::Processors::PaddleClassicProcessor,
                 Profitable::MrrCalculator.processor_for("paddle_classic")
  end

  def test_processor_for_returns_base_processor_for_unknown
    assert_equal Profitable::Processors::Base,
                 Profitable::MrrCalculator.processor_for("unknown")
  end

  def test_processor_for_returns_base_processor_for_nil
    assert_equal Profitable::Processors::Base,
                 Profitable::MrrCalculator.processor_for(nil)
  end

  # ============================================================================
  # REGRESSION: Pay v10+ object column support
  # ============================================================================

  def test_calculates_mrr_correctly_with_pay_v10_object_column
    # REGRESSION TEST: This was the original bug
    # Pay v10+ stores Stripe objects in `object` column, not `data`
    subscription = create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month"
    )

    # Verify the subscription has object but not data
    refute_nil subscription.object
    assert_nil subscription.data

    # MRR should still calculate correctly
    assert_equal 9900, Profitable::MrrCalculator.calculate
  end

  def test_calculates_mrr_correctly_with_legacy_data_column
    # REGRESSION TEST: Ensure backwards compatibility
    subscription = create_stripe_subscription_legacy(
      customer: @stripe_customer,
      unit_amount: 9900,
      interval: "month"
    )

    # Verify the subscription has data but not object
    assert_nil subscription.object
    refute_nil subscription.data

    # MRR should still calculate correctly
    assert_equal 9900, Profitable::MrrCalculator.calculate
  end

  # ============================================================================
  # EDGE CASES
  # ============================================================================

  def test_handles_large_number_of_subscriptions
    # Create 100 subscriptions
    100.times do
      create_stripe_subscription_v10(
        customer: create_customer(processor: "stripe"),
        unit_amount: 100,  # $1/month each
        interval: "month"
      )
    end

    assert_equal 10000, Profitable::MrrCalculator.calculate  # $100/month total
  end

  def test_handles_subscriptions_with_zero_amount
    # A $0 subscription (free tier?)
    Pay::Subscription.create!(
      customer: @stripe_customer,
      processor_id: "sub_free",
      name: "default",
      status: "active",
      object: {
        "items" => {
          "data" => [
            {
              "quantity" => 1,
              "price" => {
                "unit_amount" => 0,
                "recurring" => { "interval" => "month", "interval_count" => 1 }
              }
            }
          ]
        }
      }
    )

    # Another $50/month subscription
    create_stripe_subscription_v10(
      customer: @stripe_customer,
      unit_amount: 5000,
      interval: "month"
    )

    assert_equal 5000, Profitable::MrrCalculator.calculate
  end
end
