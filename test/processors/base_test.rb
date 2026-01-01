# frozen_string_literal: true

require "test_helper"

class ProcessorsBaseTest < Minitest::Test
  # ============================================================================
  # SETUP
  # ============================================================================

  def setup
    super
    @customer = create_customer(processor: "stripe")
    @subscription = create_stripe_subscription_v10(
      customer: @customer,
      unit_amount: 9900,
      interval: "month"
    )
    @processor = Profitable::Processors::Base.new(@subscription)
  end

  # ============================================================================
  # BASE CALCULATE_MRR (always returns 0, must be overridden)
  # ============================================================================

  def test_base_calculate_mrr_returns_zero
    assert_equal 0, @processor.calculate_mrr
  end

  # ============================================================================
  # SUBSCRIPTION_DATA BACKWARDS COMPATIBILITY
  # ============================================================================

  def test_subscription_data_returns_object_when_present
    # v10+ uses object column
    data = @processor.send(:subscription_data)

    assert_equal @subscription.object, data
  end

  def test_subscription_data_returns_data_when_object_is_nil
    # Pre-v10 uses data column
    legacy_subscription = create_stripe_subscription_legacy(
      customer: @customer,
      unit_amount: 5000,
      interval: "month"
    )
    processor = Profitable::Processors::Base.new(legacy_subscription)
    data = processor.send(:subscription_data)

    assert_equal legacy_subscription.data, data
  end

  def test_subscription_data_returns_nil_when_both_nil
    @subscription.update!(object: nil, data: nil)
    data = @processor.send(:subscription_data)

    assert_nil data
  end

  # ============================================================================
  # NORMALIZE_TO_MONTHLY: MONTHLY INTERVALS
  # ============================================================================

  def test_normalize_to_monthly_for_monthly_subscription
    # $99/month should return 9900 cents
    result = @processor.send(:normalize_to_monthly, 9900, "month", 1)

    assert_equal 9900, result
  end

  def test_normalize_to_monthly_for_quarterly_subscription
    # $297/quarter = $99/month
    result = @processor.send(:normalize_to_monthly, 29700, "month", 3)

    assert_equal 9900, result
  end

  def test_normalize_to_monthly_for_biannual_subscription
    # $594/6 months = $99/month
    result = @processor.send(:normalize_to_monthly, 59400, "month", 6)

    assert_equal 9900, result
  end

  # ============================================================================
  # NORMALIZE_TO_MONTHLY: YEARLY INTERVALS
  # ============================================================================

  def test_normalize_to_monthly_for_yearly_subscription
    # $1188/year = $99/month
    result = @processor.send(:normalize_to_monthly, 118800, "year", 1)

    assert_equal 9900, result
  end

  def test_normalize_to_monthly_for_biennial_subscription
    # $2376/2 years = $99/month
    result = @processor.send(:normalize_to_monthly, 237600, "year", 2)

    assert_equal 9900, result
  end

  # ============================================================================
  # NORMALIZE_TO_MONTHLY: WEEKLY INTERVALS
  # ============================================================================

  def test_normalize_to_monthly_for_weekly_subscription
    # $25/week * 4 weeks = $100/month
    result = @processor.send(:normalize_to_monthly, 2500, "week", 1)

    assert_equal 10000, result
  end

  def test_normalize_to_monthly_for_biweekly_subscription
    # $50/2 weeks * 2 = $100/month
    result = @processor.send(:normalize_to_monthly, 5000, "week", 2)

    assert_equal 10000, result
  end

  # ============================================================================
  # NORMALIZE_TO_MONTHLY: DAILY INTERVALS
  # ============================================================================

  def test_normalize_to_monthly_for_daily_subscription
    # $10/day * 30 days = $300/month
    result = @processor.send(:normalize_to_monthly, 1000, "day", 1)

    assert_equal 30000, result
  end

  def test_normalize_to_monthly_for_every_other_day_subscription
    # $20/2 days * 15 = $150/month
    result = @processor.send(:normalize_to_monthly, 2000, "day", 2)

    assert_equal 30000, result
  end

  # ============================================================================
  # NORMALIZE_TO_MONTHLY: EDGE CASES AND ERROR HANDLING
  # ============================================================================

  def test_normalize_to_monthly_returns_zero_for_nil_amount
    result = @processor.send(:normalize_to_monthly, nil, "month", 1)

    assert_equal 0, result
  end

  def test_normalize_to_monthly_returns_zero_for_nil_interval
    result = @processor.send(:normalize_to_monthly, 9900, nil, 1)

    assert_equal 0, result
  end

  def test_normalize_to_monthly_returns_zero_for_nil_interval_count
    result = @processor.send(:normalize_to_monthly, 9900, "month", nil)

    assert_equal 0, result
  end

  def test_normalize_to_monthly_returns_zero_for_zero_interval_count
    # REGRESSION TEST: Prevent division by zero
    result = @processor.send(:normalize_to_monthly, 9900, "month", 0)

    assert_equal 0, result
  end

  def test_normalize_to_monthly_returns_zero_for_unknown_interval
    result = @processor.send(:normalize_to_monthly, 9900, "decade", 1)

    assert_equal 0, result
  end

  def test_normalize_to_monthly_handles_uppercase_interval
    result = @processor.send(:normalize_to_monthly, 9900, "MONTH", 1)

    assert_equal 9900, result
  end

  def test_normalize_to_monthly_handles_mixed_case_interval
    result = @processor.send(:normalize_to_monthly, 9900, "Month", 1)

    assert_equal 9900, result
  end

  # ============================================================================
  # NORMALIZE_TO_MONTHLY: ROUNDING CONSISTENCY
  # ============================================================================

  def test_normalize_to_monthly_always_returns_integer
    # REGRESSION TEST: Ensure consistent integer return (cents)
    # $100/year = $8.333.../month = 833 cents (rounded)
    result = @processor.send(:normalize_to_monthly, 10000, "year", 1)

    assert_kind_of Integer, result
    assert_equal 833, result
  end

  def test_normalize_to_monthly_rounds_correctly_for_odd_amounts
    # $10/year = $0.833.../month = 83 cents (rounded)
    result = @processor.send(:normalize_to_monthly, 1000, "year", 1)

    assert_kind_of Integer, result
    assert_equal 83, result
  end

  def test_normalize_to_monthly_handles_fractional_weekly
    # $7/week * 4 = $28/month = 2800 cents
    result = @processor.send(:normalize_to_monthly, 700, "week", 1)

    assert_kind_of Integer, result
    assert_equal 2800, result
  end

  # ============================================================================
  # NORMALIZE_TO_MONTHLY: STRING COERCION
  # ============================================================================

  def test_normalize_to_monthly_handles_string_amount
    result = @processor.send(:normalize_to_monthly, "9900", "month", 1)

    assert_equal 9900, result
  end

  def test_normalize_to_monthly_handles_string_interval_count
    result = @processor.send(:normalize_to_monthly, 9900, "month", "3")

    assert_equal 3300, result
  end

  def test_normalize_to_monthly_handles_symbol_interval
    result = @processor.send(:normalize_to_monthly, 9900, :month, 1)

    assert_equal 9900, result
  end
end
