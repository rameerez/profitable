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

  # ============================================================================
  # SUBSCRIBER COUNTS
  # ============================================================================

  def test_total_customers_counts_customers_with_charges
    create_successful_charge(customer: @customer, amount: 5000)

    customer2 = create_customer(processor: "stripe")
    create_successful_charge(customer: customer2, amount: 3000)

    assert_equal 2, Profitable.total_customers.to_i
  end

  def test_total_subscribers_counts_customers_with_subscriptions
    create_stripe_subscription_v10(customer: @customer, unit_amount: 9900, interval: "month")

    customer2 = create_customer(processor: "stripe")
    create_stripe_subscription_v10(customer: customer2, unit_amount: 4900, interval: "month")

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

  # ============================================================================
  # NEW CUSTOMERS AND SUBSCRIBERS
  # ============================================================================

  def test_new_customers_in_period
    # Customer created 60 days ago (outside period)
    old_customer = create_customer(processor: "stripe")
    old_customer.update!(created_at: 60.days.ago)
    create_successful_charge(customer: old_customer, amount: 5000)

    # New customer
    new_customer = create_customer(processor: "stripe")
    create_successful_charge(customer: new_customer, amount: 3000)

    assert_equal 1, Profitable.new_customers(in_the_last: 30.days).to_i
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
