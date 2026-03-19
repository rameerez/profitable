# frozen_string_literal: true

require "test_helper"

class ProfitableTest < Minitest::Test
  # ============================================================================
  # SETUP
  # ============================================================================

  def setup
    super
    @customer = create_customer(processor: "stripe")
  end

  # ============================================================================
  # MRR (Monthly Recurring Revenue)
  # ============================================================================

  def test_mrr_returns_numeric_result
    assert_kind_of Profitable::NumericResult, Profitable.mrr
  end

  def test_mrr_returns_zero_when_no_subscriptions
    assert_equal 0, Profitable.mrr.to_i
  end

  def test_mrr_calculates_correctly
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )

    assert_equal 9900, Profitable.mrr.to_i
  end

  def test_mrr_excludes_subscriptions_still_on_trial_even_if_status_is_active
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )
    subscription.update!(trial_ends_at: 5.days.from_now)

    assert_equal 0, Profitable.mrr.to_i
  end

  def test_mrr_excludes_on_trial_status_until_trial_ends
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "on_trial"
    )
    subscription.update!(trial_ends_at: 5.days.from_now)

    assert_equal 0, Profitable.mrr.to_i
  end

  def test_mrr_includes_past_due_subscriptions
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "past_due"
    )

    assert_equal 9900, Profitable.mrr.to_i
  end

  def test_mrr_includes_cancel_at_period_end_subscriptions_still_in_grace_period
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "canceled"
    )
    subscription.update!(ends_at: 5.days.from_now)

    assert_equal 9900, Profitable.mrr.to_i
  end

  def test_mrr_excludes_incomplete_and_unpaid_subscriptions
    create_stripe_subscription_v10(
      customer: @customer,
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

    assert_equal 0, Profitable.mrr.to_i
  end

  def test_mrr_to_readable_formats_as_currency
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )

    assert_equal "$99", Profitable.mrr.to_readable
  end

  # ============================================================================
  # ARR (Annual Recurring Revenue)
  # ============================================================================

  def test_arr_returns_numeric_result
    assert_kind_of Profitable::NumericResult, Profitable.arr
  end

  def test_arr_is_twelve_times_mrr
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,  # $100/month
      interval: "month"
    )

    # MRR: $100/month = 10000 cents
    # ARR: $1200/year = 120000 cents
    assert_equal 120000, Profitable.arr.to_i
  end

  def test_arr_returns_integer
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,  # $99/month
      interval: "month"
    )

    # REGRESSION TEST: ARR should return integer cents
    result = Profitable.arr.to_i

    assert_kind_of Integer, result
    assert_equal 118800, result  # $1188/year
  end

  # ============================================================================
  # CHURN
  # ============================================================================

  def test_churn_returns_numeric_result_with_percentage_type
    result = Profitable.churn

    assert_kind_of Profitable::NumericResult, result
    assert_equal "0%", result.to_readable(0)
  end

  def test_churn_returns_zero_when_no_subscribers
    assert_equal 0, Profitable.churn.to_f
  end

  def test_churn_calculates_percentage
    # Create a customer who was subscribed and then churned
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )

    # Backdate the subscription to 60 days ago
    subscription.update!(created_at: 60.days.ago)

    # Create another customer who churned (subscription ended 15 days ago)
    churned_customer = create_customer(processor: "stripe")
    churned_sub = create_stripe_subscription_v10(
      customer: churned_customer,
      unit_amount: 9900,
      interval: "month",
      status: "canceled"
    )
    churned_sub.update!(
      created_at: 45.days.ago,
      ends_at: 15.days.ago
    )

    # Churn = churned customers / total subscribers at start of period
    churn = Profitable.churn(in_the_last: 30.days).to_f

    assert churn > 0, "Churn should be greater than 0"
    assert churn <= 100, "Churn should be <= 100%"
  end

  def test_churn_excludes_trial_only_subscribers_from_starting_base
    active_subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )
    active_subscription.update!(created_at: 60.days.ago)

    churned_subscription = create_stripe_subscription_v10(
      customer: create_customer(processor: "stripe"),
      unit_amount: 9900,
      interval: "month",
      status: "canceled"
    )
    churned_subscription.update!(created_at: 60.days.ago, ends_at: 10.days.ago)

    converted_trial = create_stripe_subscription_v10(
      customer: create_customer(processor: "stripe"),
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )
    converted_trial.update!(created_at: 40.days.ago, trial_ends_at: 10.days.ago)

    assert_in_delta 50.0, Profitable.churn(in_the_last: 30.days).to_f, 0.01
  end

  # ============================================================================
  # ALL TIME REVENUE
  # ============================================================================

  def test_all_time_revenue_returns_numeric_result
    assert_kind_of Profitable::NumericResult, Profitable.all_time_revenue
  end

  def test_all_time_revenue_sums_all_successful_charges
    create_successful_charge(customer: @customer, amount: 5000)
    create_successful_charge(customer: @customer, amount: 3000)
    create_successful_charge(customer: @customer, amount: 2000)

    assert_equal 10000, Profitable.all_time_revenue.to_i
  end

  def test_all_time_revenue_excludes_failed_charges
    create_successful_charge(customer: @customer, amount: 5000)
    create_failed_charge(customer: @customer, amount: 10000)

    assert_equal 5000, Profitable.all_time_revenue.to_i
  end

  def test_all_time_revenue_subtracts_refunds
    create_successful_charge(customer: @customer, amount: 5000, amount_refunded: 1200)
    create_successful_charge(customer: @customer, amount: 3000)

    assert_equal 6800, Profitable.all_time_revenue.to_i
  end

  def test_all_time_revenue_treats_full_refunds_as_zero_revenue
    create_successful_charge(customer: @customer, amount: 5000, amount_refunded: 5000)

    assert_equal 0, Profitable.all_time_revenue.to_i
  end

  # ============================================================================
  # TTM REVENUE
  # ============================================================================

  def test_ttm_revenue_returns_numeric_result
    assert_kind_of Profitable::NumericResult, Profitable.ttm_revenue
  end

  def test_ttm_alias_returns_same_value_as_ttm_revenue
    create_successful_charge(customer: @customer, amount: 5000)
    create_successful_charge(customer: @customer, amount: 3000)

    assert_kind_of Profitable::NumericResult, Profitable.ttm
    assert_equal Profitable.ttm_revenue.to_i, Profitable.ttm.to_i
  end

  def test_ttm_revenue_only_includes_last_twelve_months_and_subtracts_refunds
    old_charge = create_successful_charge(customer: @customer, amount: 10000)
    old_charge.update!(created_at: 13.months.ago)

    recent_charge = create_successful_charge(customer: @customer, amount: 5000)
    recent_charge.update!(created_at: 11.months.ago)

    refunded_charge = create_successful_charge(customer: @customer, amount: 4000, amount_refunded: 1000)
    refunded_charge.update!(created_at: 1.month.ago)

    assert_equal 8000, Profitable.ttm_revenue.to_i
  end

  def test_ttm_revenue_honors_twelve_month_boundary
    included_charge = create_successful_charge(customer: @customer, amount: 5000)
    included_charge.update!(created_at: 12.months.ago + 1.second)

    excluded_charge = create_successful_charge(customer: @customer, amount: 7000)
    excluded_charge.update!(created_at: 12.months.ago - 1.second)

    assert_equal 5000, Profitable.ttm_revenue.to_i
  end

  # ============================================================================
  # REVENUE RUN RATE
  # ============================================================================

  def test_revenue_run_rate_returns_numeric_result
    assert_kind_of Profitable::NumericResult, Profitable.revenue_run_rate
  end

  def test_revenue_run_rate_annualizes_recent_revenue
    create_successful_charge(customer: @customer, amount: 5000)
    create_successful_charge(customer: @customer, amount: 3000)

    assert_equal 96000, Profitable.revenue_run_rate(in_the_last: 30.days).to_i
  end

  def test_revenue_run_rate_subtracts_refunds
    create_successful_charge(customer: @customer, amount: 5000, amount_refunded: 2000)

    assert_equal 36000, Profitable.revenue_run_rate(in_the_last: 30.days).to_i
  end

  def test_revenue_run_rate_returns_zero_for_zero_length_period
    assert_equal 0, Profitable.revenue_run_rate(in_the_last: 0.seconds).to_i
  end

  def test_revenue_run_rate_scales_non_thirty_day_periods
    create_successful_charge(customer: @customer, amount: 4000)

    assert_equal 96000, Profitable.revenue_run_rate(in_the_last: 15.days).to_i
  end

  # ============================================================================
  # REVENUE IN PERIOD
  # ============================================================================

  def test_revenue_in_period_returns_numeric_result
    assert_kind_of Profitable::NumericResult, Profitable.revenue_in_period
  end

  def test_revenue_in_period_only_includes_charges_in_period
    # Charge from 60 days ago (outside default 30 day period)
    old_charge = create_successful_charge(customer: @customer, amount: 10000)
    old_charge.update!(created_at: 60.days.ago)

    # Recent charges
    create_successful_charge(customer: @customer, amount: 5000)
    create_successful_charge(customer: @customer, amount: 3000)

    assert_equal 8000, Profitable.revenue_in_period(in_the_last: 30.days).to_i
  end

  def test_revenue_in_period_subtracts_refunds
    create_successful_charge(customer: @customer, amount: 5000, amount_refunded: 2000)
    create_successful_charge(customer: @customer, amount: 3000)

    assert_equal 6000, Profitable.revenue_in_period(in_the_last: 30.days).to_i
  end

  # ============================================================================
  # RECURRING REVENUE IN PERIOD
  # ============================================================================

  def test_recurring_revenue_in_period_only_includes_subscription_charges
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )

    # Subscription charge
    create_successful_charge(customer: @customer, amount: 9900, subscription: subscription)

    # One-time charge (not recurring)
    create_successful_charge(customer: @customer, amount: 5000)

    assert_equal 9900, Profitable.recurring_revenue_in_period(in_the_last: 30.days).to_i
  end

  def test_recurring_revenue_in_period_subtracts_refunds
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )

    create_successful_charge(
      customer: @customer,
      amount: 9900,
      amount_refunded: 1900,
      subscription: subscription
    )

    assert_equal 8000, Profitable.recurring_revenue_in_period(in_the_last: 30.days).to_i
  end

  # ============================================================================
  # RECURRING REVENUE PERCENTAGE
  # ============================================================================

  def test_recurring_revenue_percentage_returns_percentage
    result = Profitable.recurring_revenue_percentage

    assert_kind_of Profitable::NumericResult, result
  end

  def test_recurring_revenue_percentage_calculates_correctly
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )

    # $75 in subscription revenue
    create_successful_charge(customer: @customer, amount: 7500, subscription: subscription)

    # $25 in one-time revenue
    create_successful_charge(customer: @customer, amount: 2500)

    # 75% recurring
    percentage = Profitable.recurring_revenue_percentage(in_the_last: 30.days).to_f

    assert_equal 75.0, percentage
  end

  def test_recurring_revenue_percentage_returns_zero_when_no_revenue
    assert_equal 0, Profitable.recurring_revenue_percentage.to_f
  end

  # ============================================================================
  # ESTIMATED VALUATION
  # ============================================================================

  def test_estimated_valuation_uses_default_multiplier_of_3x
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,  # $100/month MRR
      interval: "month"
    )

    # ARR = $1200, Valuation @ 3x = $3600 = 360000 cents
    assert_equal 360000, Profitable.estimated_valuation.to_i
  end

  def test_estimated_valuation_accepts_custom_multiplier
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,  # $100/month MRR
      interval: "month"
    )

    # ARR = $1200, Valuation @ 5x = $6000 = 600000 cents
    assert_equal 600000, Profitable.estimated_valuation(5).to_i
  end

  def test_estimated_valuation_accepts_at_keyword
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,
      interval: "month"
    )

    assert_equal 600000, Profitable.estimated_valuation(at: 5).to_i
  end

  def test_estimated_valuation_accepts_multiple_keyword
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,
      interval: "month"
    )

    assert_equal 600000, Profitable.estimated_valuation(multiple: 5).to_i
  end

  def test_estimated_valuation_accepts_string_multiplier_with_x
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,
      interval: "month"
    )

    assert_equal 480000, Profitable.estimated_valuation("4x").to_i
  end

  def test_estimated_valuation_clamps_multiplier_range
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,
      interval: "month"
    )

    # Very high multiplier should be clamped to 100
    high_valuation = Profitable.estimated_valuation(200).to_i
    expected = (120000 * 100)  # ARR * 100

    assert_equal expected, high_valuation
  end

  def test_estimated_valuation_matches_estimated_arr_valuation
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,
      interval: "month"
    )

    assert_equal Profitable.estimated_arr_valuation(5).to_i, Profitable.estimated_valuation(5).to_i
  end

  def test_estimated_arr_valuation_clamps_low_multiplier
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,
      interval: "month"
    )

    assert_equal 12000, Profitable.estimated_arr_valuation(0).to_i
  end

  def test_estimated_ttm_revenue_valuation_uses_ttm_revenue
    charge = create_successful_charge(customer: @customer, amount: 8000)
    charge.update!(created_at: 2.months.ago)

    assert_equal 32000, Profitable.estimated_ttm_revenue_valuation(4).to_i
  end

  def test_estimated_ttm_revenue_valuation_accepts_at_keyword
    charge = create_successful_charge(customer: @customer, amount: 8000)
    charge.update!(created_at: 2.months.ago)

    assert_equal 32000, Profitable.estimated_ttm_revenue_valuation(at: 4).to_i
  end

  def test_estimated_revenue_run_rate_valuation_uses_recent_revenue_run_rate
    create_successful_charge(customer: @customer, amount: 5000)
    create_successful_charge(customer: @customer, amount: 3000)

    assert_equal 192000, Profitable.estimated_revenue_run_rate_valuation(2, in_the_last: 30.days).to_i
  end

  def test_estimated_revenue_run_rate_valuation_accepts_multiple_keyword
    create_successful_charge(customer: @customer, amount: 5000)
    create_successful_charge(customer: @customer, amount: 3000)

    assert_equal 192000, Profitable.estimated_revenue_run_rate_valuation(multiple: 2, in_the_last: 30.days).to_i
  end

  # ============================================================================
  # SUBSCRIBER COUNTS
  # ============================================================================

  def test_total_customers_counts_customers_with_charges_and_billable_subscriptions
    create_successful_charge(customer: @customer, amount: 5000)

    customer2 = create_customer(processor: "stripe")
    create_successful_charge(customer: customer2, amount: 3000)

    customer3 = create_customer(processor: "stripe")
    subscription = create_stripe_subscription_v10(customer: customer3, unit_amount: 4900, interval: "month")
    subscription.update!(created_at: 45.days.ago, trial_ends_at: 15.days.ago)

    assert_equal 3, Profitable.total_customers.to_i
  end

  def test_total_customers_excludes_trial_only_and_incomplete_subscriptions_without_charges
    trial_subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "trialing"
    )
    trial_subscription.update!(trial_ends_at: 7.days.from_now)

    create_stripe_subscription_v10(
      customer: create_customer(processor: "stripe"),
      unit_amount: 4900,
      interval: "month",
      status: "incomplete"
    )

    assert_equal 0, Profitable.total_customers.to_i
  end

  def test_total_subscribers_counts_customers_with_subscriptions
    create_stripe_subscription_v10(customer: @customer, unit_amount: 9900, interval: "month")

    customer2 = create_customer(processor: "stripe")
    create_stripe_subscription_v10(customer: customer2, unit_amount: 4900, interval: "month")

    assert_equal 2, Profitable.total_subscribers.to_i
  end

  def test_total_subscribers_excludes_trial_only_subscriptions
    create_stripe_subscription_v10(customer: @customer, unit_amount: 9900, interval: "month")

    trial_customer = create_customer(processor: "stripe")
    trial_subscription = create_stripe_subscription_v10(
      customer: trial_customer,
      unit_amount: 4900,
      interval: "month",
      status: "trialing"
    )
    trial_subscription.update!(trial_ends_at: 7.days.from_now)

    assert_equal 1, Profitable.total_subscribers.to_i
  end

  def test_total_subscribers_includes_converted_trials
    converted_trial = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )
    converted_trial.update!(created_at: 45.days.ago, trial_ends_at: 15.days.ago)

    assert_equal 1, Profitable.total_subscribers.to_i
  end

  def test_total_subscribers_includes_cancelled_and_deleted_subscriptions_that_became_billable
    cancelled_subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "cancelled"
    )
    cancelled_subscription.update!(created_at: 45.days.ago, trial_ends_at: 30.days.ago, ends_at: 5.days.ago)

    deleted_subscription = create_stripe_subscription_v10(
      customer: create_customer(processor: "stripe"),
      unit_amount: 4900,
      interval: "month",
      status: "deleted"
    )
    deleted_subscription.update!(created_at: 45.days.ago, ends_at: 5.days.ago)

    assert_equal 2, Profitable.total_subscribers.to_i
  end

  def test_active_subscribers_counts_only_active_subscriptions
    # Active subscription
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )

    # Canceled subscription
    customer2 = create_customer(processor: "stripe")
    create_stripe_subscription_v10(
      customer: customer2,
      unit_amount: 4900,
      interval: "month",
      status: "canceled"
    )

    assert_equal 1, Profitable.active_subscribers.to_i
  end

  def test_active_subscribers_includes_past_due_and_active_subscriptions_with_future_end_dates
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "past_due"
    )

    scheduled_end = create_stripe_subscription_v10(
      customer: create_customer(processor: "stripe"),
      unit_amount: 4900,
      interval: "month",
      status: "active"
    )
    scheduled_end.update!(ends_at: 5.days.from_now)

    assert_equal 2, Profitable.active_subscribers.to_i
  end

  def test_active_subscribers_includes_cancelled_subscriptions_still_in_grace_period
    cancelled_subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "cancelled"
    )
    cancelled_subscription.update!(ends_at: 5.days.from_now)

    assert_equal 1, Profitable.active_subscribers.to_i
  end

  # ============================================================================
  # NEW CUSTOMERS AND SUBSCRIBERS
  # ============================================================================

  def test_new_customers_in_period
    # Existing signup who first paid outside the period
    old_customer = create_customer(processor: "stripe")
    old_customer.update!(created_at: 60.days.ago)
    old_charge = create_successful_charge(customer: old_customer, amount: 5000)
    old_charge.update!(created_at: 60.days.ago)

    # Existing signup who first became a customer inside the period
    existing_signup = create_customer(processor: "stripe")
    existing_signup.update!(created_at: 60.days.ago)
    create_successful_charge(customer: existing_signup, amount: 3000)

    # Truly new signup who also monetized inside the period
    new_customer = create_customer(processor: "stripe")
    create_successful_charge(customer: new_customer, amount: 4000)

    assert_equal 2, Profitable.new_customers(in_the_last: 30.days).to_i
  end

  def test_new_customers_uses_trial_conversion_date_for_subscription_only_customers
    trial_subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )
    trial_subscription.update!(created_at: 25.days.ago, trial_ends_at: 5.days.ago)

    assert_equal 1, Profitable.new_customers(in_the_last: 10.days).to_i
    assert_equal 0, Profitable.new_customers(in_the_last: 3.days).to_i
  end

  def test_new_customers_uses_earliest_monetization_event
    create_successful_charge(customer: @customer, amount: 5000, created_at: 60.days.ago)

    later_subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )
    later_subscription.update!(created_at: 10.days.ago)

    assert_equal 0, Profitable.new_customers(in_the_last: 30.days).to_i
  end

  def test_new_subscribers_counts_new_subscriptions_in_period
    # REGRESSION TEST: Should count by subscription created_at, not customer created_at
    old_subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )
    old_subscription.update!(created_at: 60.days.ago)

    # New subscription
    new_customer = create_customer(processor: "stripe")
    create_stripe_subscription_v10(
      customer: new_customer,
      unit_amount: 4900,
      interval: "month"
    )

    assert_equal 1, Profitable.new_subscribers(in_the_last: 30.days).to_i
  end

  def test_new_subscribers_uses_trial_conversion_date
    trial_subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )
    trial_subscription.update!(created_at: 25.days.ago, trial_ends_at: 5.days.ago)

    assert_equal 1, Profitable.new_subscribers(in_the_last: 10.days).to_i
    assert_equal 0, Profitable.new_subscribers(in_the_last: 3.days).to_i
  end

  def test_new_subscribers_excludes_incomplete_and_unpaid_subscriptions
    create_stripe_subscription_v10(
      customer: @customer,
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

    assert_equal 0, Profitable.new_subscribers(in_the_last: 30.days).to_i
  end

  def test_new_subscribers_excludes_on_trial_subscriptions_until_trial_ends
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "on_trial"
    )
    subscription.update!(trial_ends_at: 5.days.from_now)

    assert_equal 0, Profitable.new_subscribers(in_the_last: 30.days).to_i
  end

  # ============================================================================
  # CHURNED CUSTOMERS
  # ============================================================================

  def test_churned_customers_counts_ended_subscriptions
    # Active subscription
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )

    # Churned subscription
    churned_customer = create_customer(processor: "stripe")
    churned_sub = create_stripe_subscription_v10(
      customer: churned_customer,
      unit_amount: 4900,
      interval: "month",
      status: "canceled"
    )
    churned_sub.update!(ends_at: 10.days.ago)

    assert_equal 1, Profitable.churned_customers(in_the_last: 30.days).to_i
  end

  def test_churned_customers_counts_cancelled_and_deleted_status_aliases
    cancelled_customer = create_customer(processor: "stripe")
    cancelled_subscription = create_stripe_subscription_v10(
      customer: cancelled_customer,
      unit_amount: 4900,
      interval: "month",
      status: "cancelled"
    )
    cancelled_subscription.update!(created_at: 45.days.ago, ends_at: 10.days.ago)

    deleted_customer = create_customer(processor: "stripe")
    deleted_subscription = create_stripe_subscription_v10(
      customer: deleted_customer,
      unit_amount: 3900,
      interval: "month",
      status: "deleted"
    )
    deleted_subscription.update!(created_at: 45.days.ago, ends_at: 8.days.ago)

    assert_equal 2, Profitable.churned_customers(in_the_last: 30.days).to_i
  end

  # ============================================================================
  # NEW MRR
  # ============================================================================

  def test_new_mrr_calculates_mrr_from_new_subscriptions
    # Old subscription (outside period)
    old_sub = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 5000,
      interval: "month"
    )
    old_sub.update!(created_at: 60.days.ago)

    # New subscription
    new_customer = create_customer(processor: "stripe")
    create_stripe_subscription_v10(
      customer: new_customer,
      unit_amount: 9900,
      interval: "month"
    )

    # REGRESSION TEST: Should be full MRR, not prorated
    assert_equal 9900, Profitable.new_mrr(in_the_last: 30.days).to_i
  end

  def test_new_mrr_excludes_trialing_subscriptions
    # New trialing subscription
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "trialing"
    )

    assert_equal 0, Profitable.new_mrr(in_the_last: 30.days).to_i
  end

  def test_new_mrr_counts_subscriptions_that_churned_later_in_period
    churned_sub = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "canceled"
    )
    churned_sub.update!(created_at: 20.days.ago, ends_at: 5.days.ago)

    assert_equal 9900, Profitable.new_mrr(in_the_last: 30.days).to_i
  end

  def test_new_mrr_uses_trial_conversion_date
    trial_subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )
    trial_subscription.update!(created_at: 25.days.ago, trial_ends_at: 5.days.ago)

    assert_equal 9900, Profitable.new_mrr(in_the_last: 10.days).to_i
    assert_equal 0, Profitable.new_mrr(in_the_last: 3.days).to_i
  end

  def test_new_mrr_excludes_incomplete_and_unpaid_subscriptions
    create_stripe_subscription_v10(
      customer: @customer,
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

    assert_equal 0, Profitable.new_mrr(in_the_last: 30.days).to_i
  end

  def test_new_mrr_excludes_on_trial_subscriptions_until_trial_ends
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "on_trial"
    )
    subscription.update!(trial_ends_at: 5.days.from_now)

    assert_equal 0, Profitable.new_mrr(in_the_last: 30.days).to_i
  end

  # ============================================================================
  # CHURNED MRR
  # ============================================================================

  def test_churned_mrr_calculates_mrr_lost
    # Churned subscription
    churned_sub = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "canceled"
    )
    churned_sub.update!(
      created_at: 45.days.ago,
      ends_at: 10.days.ago
    )

    # REGRESSION TEST: Should be full MRR, not prorated
    assert_equal 9900, Profitable.churned_mrr(in_the_last: 30.days).to_i
  end

  def test_churned_mrr_counts_cancelled_and_deleted_status_aliases
    cancelled_subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 4900,
      interval: "month",
      status: "cancelled"
    )
    cancelled_subscription.update!(created_at: 45.days.ago, ends_at: 10.days.ago)

    deleted_subscription = create_stripe_subscription_v10(
      customer: create_customer(processor: "stripe"),
      unit_amount: 3900,
      interval: "month",
      status: "deleted"
    )
    deleted_subscription.update!(created_at: 45.days.ago, ends_at: 8.days.ago)

    assert_equal 8800, Profitable.churned_mrr(in_the_last: 30.days).to_i
  end

  # ============================================================================
  # AVERAGE REVENUE PER CUSTOMER
  # ============================================================================

  def test_average_revenue_per_customer_calculates_correctly
    # Customer 1: $100 total
    create_successful_charge(customer: @customer, amount: 10000)

    # Customer 2: $50 total
    customer2 = create_customer(processor: "stripe")
    create_successful_charge(customer: customer2, amount: 5000)

    # Average: $75 = 7500 cents
    assert_equal 7500, Profitable.average_revenue_per_customer.to_i
  end

  def test_average_revenue_per_customer_returns_zero_when_no_customers
    assert_equal 0, Profitable.average_revenue_per_customer.to_i
  end

  # ============================================================================
  # LIFETIME VALUE (LTV)
  # ============================================================================

  def test_lifetime_value_returns_numeric_result
    assert_kind_of Profitable::NumericResult, Profitable.lifetime_value
  end

  def test_lifetime_value_returns_zero_when_no_subscribers
    assert_equal 0, Profitable.lifetime_value.to_i
  end

  def test_lifetime_value_returns_zero_when_no_churn
    # Active subscription with no churn
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )

    # LTV = ARPU / churn_rate
    # When churn is 0, LTV should return 0 (not infinity)
    assert_equal 0, Profitable.lifetime_value.to_i
  end

  def test_lifetime_value_calculates_correctly
    # REGRESSION TEST: LTV = Monthly ARPU / Monthly Churn Rate
    # Setup: 2 active subscriptions at $99/month, 1 churned
    subscription1 = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )
    subscription1.update!(created_at: 60.days.ago)

    customer2 = create_customer(processor: "stripe")
    subscription2 = create_stripe_subscription_v10(
      customer: customer2,
      unit_amount: 9900,
      interval: "month"
    )
    subscription2.update!(created_at: 60.days.ago)

    churned_customer = create_customer(processor: "stripe")
    churned_sub = create_stripe_subscription_v10(
      customer: churned_customer,
      unit_amount: 9900,
      interval: "month",
      status: "canceled"
    )
    churned_sub.update!(
      created_at: 60.days.ago,
      ends_at: 15.days.ago
    )

    ltv = Profitable.lifetime_value.to_i

    # LTV should be calculated as: ARPU / churn_rate
    # ARPU = MRR / active_subscribers = 19800 / 2 = 9900
    # Churn = 1 churned / 3 at start = 33.33%
    # LTV = 9900 / 0.3333 ≈ 29700
    assert ltv > 0, "LTV should be positive when there is churn"
  end

  # ============================================================================
  # MRR GROWTH
  # ============================================================================

  def test_mrr_growth_returns_new_mrr_minus_churned_mrr
    # New subscription
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,
      interval: "month"
    )

    # Churned subscription
    churned_customer = create_customer(processor: "stripe")
    churned_sub = create_stripe_subscription_v10(
      customer: churned_customer,
      unit_amount: 5000,
      interval: "month",
      status: "canceled"
    )
    churned_sub.update!(
      created_at: 45.days.ago,
      ends_at: 15.days.ago
    )

    # Net MRR growth = $100 new - $50 churned = $50
    assert_equal 5000, Profitable.mrr_growth(in_the_last: 30.days).to_i
  end

  def test_mrr_growth_can_be_negative
    # Churned subscription (no new subscriptions)
    churned_sub = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "canceled"
    )
    churned_sub.update!(
      created_at: 45.days.ago,
      ends_at: 15.days.ago
    )

    assert_equal(-9900, Profitable.mrr_growth(in_the_last: 30.days).to_i)
  end

  # ============================================================================
  # MRR GROWTH RATE
  # ============================================================================

  def test_mrr_growth_rate_returns_percentage
    result = Profitable.mrr_growth_rate

    assert_kind_of Profitable::NumericResult, result
  end

  def test_mrr_growth_rate_returns_zero_when_no_starting_mrr
    # No subscriptions 30 days ago
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )

    assert_equal 0, Profitable.mrr_growth_rate(in_the_last: 30.days).to_f
  end

  def test_mrr_growth_rate_uses_billable_historical_snapshots
    surviving_subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,
      interval: "month"
    )
    surviving_subscription.update!(created_at: 60.days.ago)

    churned_subscription = create_stripe_subscription_v10(
      customer: create_customer(processor: "stripe"),
      unit_amount: 5000,
      interval: "month",
      status: "canceled"
    )
    churned_subscription.update!(created_at: 60.days.ago, ends_at: 15.days.ago)

    assert_in_delta(-33.33, Profitable.mrr_growth_rate(in_the_last: 30.days).to_f, 0.01)
  end

  # ============================================================================
  # TIME TO NEXT MRR MILESTONE
  # ============================================================================

  def test_time_to_next_mrr_milestone_returns_message_when_no_mrr
    message = Profitable.time_to_next_mrr_milestone

    assert_equal "Unable to calculate. No MRR yet.", message
  end

  def test_time_to_next_mrr_milestone_returns_congratulations_at_highest_milestone
    # Create subscription with $100M+ MRR (way above highest milestone)
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 15_000_000_000,  # $150M/month
      interval: "month"
    )

    message = Profitable.time_to_next_mrr_milestone

    assert_equal "Congratulations! You've reached the highest milestone.", message
  end

  def test_time_to_next_mrr_milestone_returns_message_when_no_growth
    subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 100000,  # $1000/month
      interval: "month"
    )
    # Backdate to have same MRR 30 days ago
    subscription.update!(created_at: 60.days.ago)

    message = Profitable.time_to_next_mrr_milestone

    assert_includes message, "Unable to calculate"
  end

  # ============================================================================
  # MONTHLY SUMMARY
  # ============================================================================

  def test_monthly_summary_returns_array_of_hashes
    result = Profitable.monthly_summary(months: 3)

    assert_kind_of Array, result
    assert_equal 3, result.length
    result.each do |month_data|
      assert_kind_of Hash, month_data
      assert month_data.key?(:month)
      assert month_data.key?(:month_date)
      assert month_data.key?(:new_subscribers)
      assert month_data.key?(:churned_subscribers)
      assert month_data.key?(:net_subscribers)
      assert month_data.key?(:new_mrr)
      assert month_data.key?(:churned_mrr)
      assert month_data.key?(:net_mrr)
      assert month_data.key?(:churn_rate)
    end
  end

  def test_monthly_summary_captures_new_subscribers
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )

    result = Profitable.monthly_summary(months: 1)
    current_month = result.first

    assert_equal 1, current_month[:new_subscribers]
    assert_equal 9900, current_month[:new_mrr]
  end

  def test_monthly_summary_uses_trial_conversion_month_for_new_subscribers_and_new_mrr
    trial_subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )
    trial_subscription.update!(created_at: 40.days.ago, trial_ends_at: 5.days.ago)

    result = Profitable.monthly_summary(months: 2)
    current_month = result.last
    previous_month = result.first

    assert_equal 1, current_month[:new_subscribers]
    assert_equal 9900, current_month[:new_mrr]
    assert_equal 0, previous_month[:new_subscribers]
    assert_equal 0, previous_month[:new_mrr]
  end

  def test_monthly_summary_captures_churned_subscribers
    churned_sub = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 5000,
      interval: "month",
      status: "canceled"
    )
    churned_sub.update!(
      created_at: 60.days.ago,
      ends_at: 5.days.ago
    )

    result = Profitable.monthly_summary(months: 1)
    current_month = result.first

    assert_equal 1, current_month[:churned_subscribers]
    assert_equal 5000, current_month[:churned_mrr]
  end

  def test_monthly_summary_calculates_net_correctly
    # New subscriber this month
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )

    # Churned subscriber this month
    churned_customer = create_customer(processor: "stripe")
    churned_sub = create_stripe_subscription_v10(
      customer: churned_customer,
      unit_amount: 5000,
      interval: "month",
      status: "canceled"
    )
    churned_sub.update!(
      created_at: 60.days.ago,
      ends_at: 5.days.ago
    )

    result = Profitable.monthly_summary(months: 1)
    current_month = result.first

    assert_equal 0, current_month[:net_subscribers]  # 1 new - 1 churned
    assert_equal 4900, current_month[:net_mrr]        # 9900 - 5000
  end

  def test_monthly_summary_ordered_oldest_first
    result = Profitable.monthly_summary(months: 3)

    # Should be ordered oldest to newest
    dates = result.map { |m| m[:month_date] }
    assert_equal dates, dates.sort
  end

  # ============================================================================
  # DAILY SUMMARY
  # ============================================================================

  def test_daily_summary_returns_array_of_hashes
    result = Profitable.daily_summary(days: 7)

    assert_kind_of Array, result
    assert_equal 7, result.length
    result.each do |day_data|
      assert_kind_of Hash, day_data
      assert day_data.key?(:date)
      assert day_data.key?(:new_subscribers)
      assert day_data.key?(:churned_subscribers)
    end
  end

  def test_daily_summary_captures_new_subscriber_today
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )

    result = Profitable.daily_summary(days: 1)
    today = result.first

    assert_equal Date.current, today[:date]
    assert_equal 1, today[:new_subscribers]
  end

  def test_daily_summary_uses_trial_conversion_day_for_new_subscribers
    trial_subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )
    trial_subscription.update!(created_at: 10.days.ago, trial_ends_at: Time.current)

    result = Profitable.daily_summary(days: 2)
    today = result.last
    yesterday = result.first

    assert_equal 1, today[:new_subscribers]
    assert_equal 0, yesterday[:new_subscribers]
  end

  def test_daily_summary_captures_churned_subscriber
    churned_sub = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 5000,
      interval: "month",
      status: "canceled"
    )
    churned_sub.update!(
      created_at: 60.days.ago,
      ends_at: Time.current
    )

    result = Profitable.daily_summary(days: 1)
    today = result.first

    assert_equal 1, today[:churned_subscribers]
  end

  def test_daily_summary_ordered_oldest_first
    result = Profitable.daily_summary(days: 7)

    dates = result.map { |d| d[:date] }
    assert_equal dates, dates.sort
  end

  # ============================================================================
  # NEW SUBSCRIBERS EXCLUDES TRIALING
  # ============================================================================

  def test_new_subscribers_excludes_trialing_subscriptions
    # Trialing subscription should NOT count as a new subscriber
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "trialing"
    )

    assert_equal 0, Profitable.new_subscribers(in_the_last: 30.days).to_i
  end

  def test_new_subscribers_includes_active_subscriptions
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month",
      status: "active"
    )

    assert_equal 1, Profitable.new_subscribers(in_the_last: 30.days).to_i
  end

  # ============================================================================
  # PERIOD DATA
  # ============================================================================

  def test_period_data_returns_hash_with_all_keys
    result = Profitable.period_data(in_the_last: 30.days)

    assert_kind_of Hash, result
    [:new_customers, :churned_customers, :churn, :new_mrr, :churned_mrr, :mrr_growth, :revenue].each do |key|
      assert result.key?(key), "Missing key: #{key}"
      assert_kind_of Profitable::NumericResult, result[key]
    end
  end

  def test_period_data_matches_individual_methods
    # Active subscription
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )

    # Churned subscription
    churned_customer = create_customer(processor: "stripe")
    churned_sub = create_stripe_subscription_v10(
      customer: churned_customer,
      unit_amount: 5000,
      interval: "month",
      status: "canceled"
    )
    churned_sub.update!(created_at: 45.days.ago, ends_at: 10.days.ago)

    # Charge for revenue
    create_successful_charge(customer: @customer, amount: 9900)

    period = 30.days
    data = Profitable.period_data(in_the_last: period)

    assert_equal Profitable.new_customers(in_the_last: period).to_i, data[:new_customers].to_i
    assert_equal Profitable.churned_customers(in_the_last: period).to_i, data[:churned_customers].to_i
    assert_equal Profitable.churn(in_the_last: period).to_f, data[:churn].to_f
    assert_equal Profitable.new_mrr(in_the_last: period).to_i, data[:new_mrr].to_i
    assert_equal Profitable.churned_mrr(in_the_last: period).to_i, data[:churned_mrr].to_i
    assert_equal Profitable.mrr_growth(in_the_last: period).to_i, data[:mrr_growth].to_i
    assert_equal Profitable.revenue_in_period(in_the_last: period).to_i, data[:revenue].to_i
  end

  def test_period_data_new_mrr_and_churned_mrr
    create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 10000,
      interval: "month"
    )

    churned_customer = create_customer(processor: "stripe")
    churned_sub = create_stripe_subscription_v10(
      customer: churned_customer,
      unit_amount: 5000,
      interval: "month",
      status: "canceled"
    )
    churned_sub.update!(created_at: 45.days.ago, ends_at: 15.days.ago)

    data = Profitable.period_data(in_the_last: 30.days)

    assert_equal 10000, data[:new_mrr].to_i
    assert_equal 5000, data[:churned_mrr].to_i
    assert_equal 5000, data[:mrr_growth].to_i
  end

  def test_period_data_revenue_is_net_of_refunds
    create_successful_charge(customer: @customer, amount: 5000, amount_refunded: 2000)

    data = Profitable.period_data(in_the_last: 30.days)

    assert_equal 3000, data[:revenue].to_i
  end

  def test_period_data_new_customers_uses_first_monetization_date
    existing_signup = create_customer(processor: "stripe")
    existing_signup.update!(created_at: 60.days.ago)
    create_successful_charge(customer: existing_signup, amount: 4000)

    data = Profitable.period_data(in_the_last: 30.days)

    assert_equal 1, data[:new_customers].to_i
  end

  # ============================================================================
  # REGRESSION: paid_charges backwards compatibility
  # ============================================================================

  def test_paid_charges_works_with_v10_object_column
    # REGRESSION TEST: Charge with status in `object` column
    create_successful_charge(customer: @customer, amount: 5000)

    assert_equal 5000, Profitable.all_time_revenue.to_i
  end

  def test_paid_charges_works_with_legacy_data_column
    # REGRESSION TEST: Charge with status in `data` column
    create_successful_charge_legacy(customer: @customer, amount: 3000)

    assert_equal 3000, Profitable.all_time_revenue.to_i
  end

  def test_paid_charges_works_with_mixed_columns
    # Both v10+ and legacy charges
    create_successful_charge(customer: @customer, amount: 5000)
    create_successful_charge_legacy(customer: @customer, amount: 3000)

    assert_equal 8000, Profitable.all_time_revenue.to_i
  end
end
