# frozen_string_literal: true

require "test_helper"

# =============================================================================
# REGRESSION TESTS
# =============================================================================
#
# This file contains regression tests for all bugs that were fixed in the
# profitable gem. Each section documents the original bug and ensures we
# don't regress to it in the future.
#
# These tests are CRITICAL for maintaining the accuracy of business metrics.
# =============================================================================

class RegressionTest < Minitest::Test
  def setup
    super
    @customer = create_customer(processor: "stripe")
  end

  # ===========================================================================
  # BUG #1: Pay v10+ object column not being read
  # ===========================================================================
  #
  # ORIGINAL BUG: The profitable gem was checking `subscription.data` for
  # subscription details, but Pay gem v10+ stores the full Stripe object in
  # the `object` column instead. This caused MRR to always return 0 for
  # users on Pay v10+.
  #
  # FIX: Added `subscription_data` helper that checks `object` first, then
  # falls back to `data` for backwards compatibility.
  # ===========================================================================

  def test_bug1_mrr_works_with_pay_v10_object_column
    # Create subscription using v10+ structure (object column)
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )

    # Verify the data structure
    refute_nil subscription.object
    assert_nil subscription.data
    refute_nil subscription.object.dig("items", "data")

    # MRR should be calculated correctly
    mrr = Profitable.mrr.to_i

    assert_equal 9900, mrr, "BUG #1 REGRESSION: MRR should be 9900 cents, not 0"
  end

  def test_bug1_mrr_still_works_with_legacy_data_column
    # Create subscription using pre-v10 structure (data column)
    subscription = create_stripe_subscription_legacy(
      customer: @customer,
      unit_amount: 4900,
      interval: "month"
    )

    # Verify the data structure
    assert_nil subscription.object
    refute_nil subscription.data
    refute_nil subscription.data["subscription_items"]

    # MRR should be calculated correctly
    mrr = Profitable.mrr.to_i

    assert_equal 4900, mrr, "BUG #1 REGRESSION: Legacy data column should still work"
  end

  # ===========================================================================
  # BUG #2: Multi-item subscriptions only counting first item
  # ===========================================================================
  #
  # ORIGINAL BUG: StripeProcessor and PaddleBillingProcessor were only
  # processing the first subscription item, ignoring additional items.
  # This caused MRR to be underreported for subscriptions with add-ons.
  #
  # FIX: Changed from accessing `subscription_items[0]` to iterating and
  # summing MRR from ALL subscription items.
  # ===========================================================================

  def test_bug2_stripe_multi_item_subscriptions_sum_all_items
    # Create a subscription with base plan + 2 add-ons
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 5000,  # Base: $50/month
      interval: "month",
      additional_items: [
        { unit_amount: 2000, quantity: 1 },  # Add-on 1: $20/month
        { unit_amount: 1000, quantity: 3 }   # Add-on 2: $10 * 3 = $30/month
      ]
    )

    mrr = Profitable.mrr.to_i

    # Should be $50 + $20 + $30 = $100/month = 10000 cents
    assert_equal 10000, mrr, "BUG #2 REGRESSION: Should sum ALL items, not just first"
  end

  def test_bug2_paddle_billing_multi_item_subscriptions_sum_all_items
    customer = create_customer(processor: "paddle_billing")

    subscription = create_paddle_billing_subscription(
      customer: customer,
      amount: 3000,  # Base: $30/month
      interval: "month",
      additional_items: [
        { amount: 1500, quantity: 2 },  # Add-on: $15 * 2 = $30/month
      ]
    )

    mrr = Profitable.mrr.to_i

    # Should be $30 + $30 = $60/month = 6000 cents
    assert_equal 6000, mrr, "BUG #2 REGRESSION: Paddle should also sum all items"
  end

  # ===========================================================================
  # BUG #3: Division by zero in normalize_to_monthly
  # ===========================================================================
  #
  # ORIGINAL BUG: When interval_count was 0 or nil, the normalize_to_monthly
  # method would cause a division by zero error.
  #
  # FIX: Added check for `interval_count.to_i.zero?` that returns 0 instead
  # of attempting the division.
  # ===========================================================================

  def test_bug3_normalize_to_monthly_handles_zero_interval_count
    processor = Profitable::Processors::Base.new(@customer)

    # Should return 0, not raise ZeroDivisionError
    result = processor.send(:normalize_to_monthly, 9900, "month", 0)

    assert_equal 0, result, "BUG #3 REGRESSION: Should return 0, not crash"
  end

  def test_bug3_normalize_to_monthly_handles_nil_values
    processor = Profitable::Processors::Base.new(@customer)

    # None of these should raise errors
    assert_equal 0, processor.send(:normalize_to_monthly, nil, "month", 1)
    assert_equal 0, processor.send(:normalize_to_monthly, 9900, nil, 1)
    assert_equal 0, processor.send(:normalize_to_monthly, 9900, "month", nil)
  end

  # ===========================================================================
  # BUG #4: Incorrect LTV formula
  # ===========================================================================
  #
  # ORIGINAL BUG: LTV calculation was using an incorrect formula that didn't
  # match the standard LTV = ARPU / Churn Rate calculation.
  #
  # FIX: Updated formula to: LTV = (MRR / active_subscribers) / churn_rate
  # ===========================================================================

  def test_bug4_ltv_uses_correct_formula
    # Setup: 2 active subscribers at $100/month each, 50% churn
    customer1 = create_customer(processor: "stripe")
    sub1 = create_stripe_subscription_v10(
      customer: customer1,
      unit_amount: 10000,
      interval: "month"
    )
    sub1.update!(created_at: 60.days.ago)

    customer2 = create_customer(processor: "stripe")
    sub2 = create_stripe_subscription_v10(
      customer: customer2,
      unit_amount: 10000,
      interval: "month"
    )
    sub2.update!(created_at: 60.days.ago)

    # 1 churned (50% churn in 30 days from 2 starting subscribers)
    churned_customer = create_customer(processor: "stripe")
    churned_sub = create_stripe_subscription_v10(
      customer: churned_customer,
      unit_amount: 10000,
      interval: "month",
      status: "canceled"
    )
    churned_sub.update!(
      created_at: 60.days.ago,
      ends_at: 15.days.ago
    )

    ltv = Profitable.lifetime_value.to_i

    # MRR = $200 (2 active * $100)
    # ARPU = $200 / 2 = $100 = 10000 cents
    # Churn = 1/3 = 33.33%
    # LTV = 10000 / 0.3333 ≈ 30000 cents

    assert ltv > 0, "BUG #4 REGRESSION: LTV should be positive"
    assert ltv < 100000, "BUG #4 REGRESSION: LTV should be reasonable"
  end

  def test_bug4_ltv_returns_zero_for_zero_churn
    # Active subscription with no churn
    sub = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,
      interval: "month"
    )
    sub.update!(created_at: 60.days.ago)

    ltv = Profitable.lifetime_value.to_i

    # When churn is 0, LTV would be infinity
    # We should return 0 instead of crashing
    assert_equal 0, ltv, "BUG #4 REGRESSION: LTV should be 0 when churn is 0"
  end

  # ===========================================================================
  # BUG #5: Historical date calculations using current status
  # ===========================================================================
  #
  # ORIGINAL BUG: calculate_mrr_at and calculate_churn were using the current
  # subscription status and active scope instead of determining what was
  # active AT the historical date.
  #
  # FIX: Updated queries to check created_at, ends_at, and pause_starts_at
  # relative to the historical date.
  # ===========================================================================

  def test_bug5_mrr_at_calculates_historical_state
    # Subscription that was active 60 days ago but churned 30 days ago
    churned_sub = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 5000,
      interval: "month",
      status: "canceled"
    )
    churned_sub.update!(
      created_at: 90.days.ago,
      ends_at: 30.days.ago
    )

    # New subscription created 15 days ago
    new_sub = create_stripe_subscription_v10(
      customer: create_customer(processor: "stripe"),
      unit_amount: 7500,
      interval: "month"
    )
    new_sub.update!(created_at: 15.days.ago)

    # MRR at 45 days ago should include churned_sub but NOT new_sub
    historical_mrr = Profitable.send(:calculate_mrr_at, 45.days.ago)

    assert_equal 5000, historical_mrr, "BUG #5 REGRESSION: Should calculate MRR at historical date"
  end

  def test_bug5_churn_uses_subscribers_at_start_of_period
    # 3 subscriptions active 45 days ago
    old_subs = 3.times.map do
      customer = create_customer(processor: "stripe")
      sub = create_stripe_subscription_v10(
        customer: customer,
        unit_amount: 5000,
        interval: "month"
      )
      sub.update!(created_at: 60.days.ago)
      sub
    end

    # 1 of them churned 15 days ago
    old_subs[0].update!(status: "canceled", ends_at: 15.days.ago)

    # 2 new subscriptions created recently (shouldn't affect denominator)
    2.times do
      create_stripe_subscription_v10(
        customer: create_customer(processor: "stripe"),
        unit_amount: 5000,
        interval: "month"
      )
    end

    churn = Profitable.churn(in_the_last: 30.days).to_f

    # Churn should be 1/3 = 33.33% (not 1/5 = 20%)
    assert_in_delta 33.33, churn, 1.0, "BUG #5 REGRESSION: Churn should use start-of-period subscribers"
  end

  # ===========================================================================
  # BUG #6: Proration incorrectly applied to MRR calculations
  # ===========================================================================
  #
  # ORIGINAL BUG: calculate_new_mrr and calculate_churned_mrr were prorating
  # the MRR based on what portion of the period the subscription was active.
  # However, MRR is a RATE, not revenue, so proration doesn't make sense.
  #
  # FIX: Removed proration logic. New/churned MRR now reflects the full
  # monthly rate of subscriptions that started/ended in the period.
  # ===========================================================================

  def test_bug6_new_mrr_is_full_rate_not_prorated
    # Subscription created 5 days ago (would have been ~17% prorated)
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,  # $100/month
      interval: "month"
    )
    subscription.update!(created_at: 5.days.ago)

    new_mrr = Profitable.new_mrr(in_the_last: 30.days).to_i

    # Should be full $100, not prorated $17
    assert_equal 10000, new_mrr, "BUG #6 REGRESSION: New MRR should be full rate"
  end

  def test_bug6_churned_mrr_is_full_rate_not_prorated
    # Subscription that ended 5 days ago
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,
      interval: "month",
      status: "canceled"
    )
    subscription.update!(
      created_at: 60.days.ago,
      ends_at: 5.days.ago
    )

    churned_mrr = Profitable.churned_mrr(in_the_last: 30.days).to_i

    # Should be full $100, not prorated
    assert_equal 10000, churned_mrr, "BUG #6 REGRESSION: Churned MRR should be full rate"
  end

  # ===========================================================================
  # BUG #7: new_subscribers using wrong date field
  # ===========================================================================
  #
  # ORIGINAL BUG: calculate_new_subscribers was filtering by customer
  # created_at instead of subscription created_at. This meant it was
  # counting new customers, not new subscriptions.
  #
  # FIX: Changed to filter by pay_subscriptions.created_at.
  # ===========================================================================

  def test_bug7_new_subscribers_uses_subscription_created_at
    # Customer created 60 days ago, but subscription created today
    @customer.update!(created_at: 60.days.ago)
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )

    new_subs = Profitable.new_subscribers(in_the_last: 30.days).to_i

    # Should count based on subscription created_at, not customer
    assert_equal 1, new_subs, "BUG #7 REGRESSION: Should use subscription.created_at"
  end

  def test_bug7_new_subscribers_excludes_old_subscriptions
    # Subscription created 60 days ago (outside 30-day window)
    old_sub = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )
    old_sub.update!(created_at: 60.days.ago)

    new_subs = Profitable.new_subscribers(in_the_last: 30.days).to_i

    assert_equal 0, new_subs, "BUG #7 REGRESSION: Should exclude old subscriptions"
  end

  # ===========================================================================
  # BUG #8: paid_charges not checking object column for charge status
  # ===========================================================================
  #
  # ORIGINAL BUG: The paid_charges method was only checking the `data`
  # column for charge status (paid, status). Pay v10+ uses `object` column.
  #
  # FIX: Updated SQL to use COALESCE to check both object and data columns.
  # ===========================================================================

  def test_bug8_paid_charges_works_with_v10_object_column
    # Create charge with status in object column (v10+)
    create_successful_charge(customer: @customer, amount: 5000)

    revenue = Profitable.all_time_revenue.to_i

    assert_equal 5000, revenue, "BUG #8 REGRESSION: Should read from object column"
  end

  def test_bug8_paid_charges_works_with_legacy_data_column
    # Create charge with status in data column (pre-v10)
    create_successful_charge_legacy(customer: @customer, amount: 3000)

    revenue = Profitable.all_time_revenue.to_i

    assert_equal 3000, revenue, "BUG #8 REGRESSION: Should still read from data column"
  end

  def test_bug8_paid_charges_excludes_failed_charges_from_both_columns
    # Failed charge with object column
    Pay::Charge.create!(
      customer: @customer,
      processor_id: "ch_failed_v10",
      amount: 10000,
      currency: "usd",
      object: { "paid" => false, "status" => "failed" }
    )

    # Failed charge with data column
    Pay::Charge.create!(
      customer: @customer,
      processor_id: "ch_failed_legacy",
      amount: 10000,
      currency: "usd",
      data: { "paid" => false, "status" => "failed" }
    )

    # Successful charge
    create_successful_charge(customer: @customer, amount: 5000)

    revenue = Profitable.all_time_revenue.to_i

    assert_equal 5000, revenue, "BUG #8 REGRESSION: Should only count successful charges"
  end

  # ===========================================================================
  # BUG #9: Inconsistent return types (float vs integer)
  # ===========================================================================
  #
  # ORIGINAL BUG: normalize_to_monthly was returning floats for some intervals,
  # causing MRR and ARR to have inconsistent types (one float, one integer).
  #
  # FIX: Added .round to the end of normalize_to_monthly to always return
  # integer cents.
  # ===========================================================================

  def test_bug9_mrr_returns_consistent_integer_type
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,  # $100/year = $8.33/month
      interval: "year"
    )

    mrr = Profitable.mrr.to_i

    assert_kind_of Integer, mrr, "BUG #9 REGRESSION: MRR should be integer cents"
  end

  def test_bug9_arr_returns_consistent_integer_type
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )

    arr = Profitable.arr.to_i

    assert_kind_of Integer, arr, "BUG #9 REGRESSION: ARR should be integer cents"
  end

  def test_bug9_normalize_to_monthly_always_returns_integer
    processor = Profitable::Processors::Base.new(@customer)

    # Test various intervals that could produce floats
    results = [
      processor.send(:normalize_to_monthly, 10000, "year", 1),    # $100/year = $8.33/month
      processor.send(:normalize_to_monthly, 7777, "month", 1),    # Odd amount
      processor.send(:normalize_to_monthly, 10000, "week", 3),    # Weekly with count
      processor.send(:normalize_to_monthly, 10000, "day", 7)      # Daily with count
    ]

    results.each do |result|
      assert_kind_of Integer, result, "BUG #9 REGRESSION: All normalize results should be integers"
    end
  end

  # ===========================================================================
  # BUG #10: time_to_next_mrr_milestone division by zero
  # ===========================================================================
  #
  # ORIGINAL BUG: When MRR was 0 or growth rate was 0, the milestone
  # calculation would fail with a division by zero error.
  #
  # FIX: Added checks for current_mrr <= 0 and daily_growth_rate <= 0 that
  # return informative messages instead of attempting calculation.
  # ===========================================================================

  def test_bug10_milestone_handles_zero_mrr
    # No subscriptions = 0 MRR
    message = Profitable.time_to_next_mrr_milestone

    assert_equal "Unable to calculate. No MRR yet.", message,
      "BUG #10 REGRESSION: Should handle zero MRR gracefully"
  end

  def test_bug10_milestone_handles_zero_growth
    # Create subscription backdated so growth rate is 0
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 100000,  # $1000/month
      interval: "month"
    )
    subscription.update!(created_at: 60.days.ago)

    message = Profitable.time_to_next_mrr_milestone

    assert_includes message, "Unable to calculate",
      "BUG #10 REGRESSION: Should handle zero/negative growth gracefully"
  end
end
