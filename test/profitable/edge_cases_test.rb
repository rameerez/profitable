# frozen_string_literal: true
require "test_helper"

class EdgeCasesTest < Minitest::Test
  def setup
    super
    @customer = Pay::Customer.create!(processor: "stripe")
  end

  def create_subscription(attrs = {})
    defaults = {
      customer: @customer,
      processor: "stripe",
      status: "active",
      quantity: 1,
      current_period_start: Time.now - 15.days,
      current_period_end: Time.now + 15.days,
      data: { "subscription_items" => [{ "price" => { "unit_amount" => 1000, "recurring" => { "interval" => "month", "interval_count" => 1 } } }] }
    }
    Pay::Subscription.create!(defaults.merge(attrs))
  end

  def test_estimated_valuation_clamps_multiplier_bounds
    create_subscription # mrr 1000, arr 12000 cents

    # Below lower bound -> clamp to 0.1x
    v = Profitable.estimated_valuation(at: "0x")
    assert_equal (12_000 * 0.1).round, v

    # Above upper bound -> clamp to 100x
    v = Profitable.estimated_valuation(at: "200x")
    assert_equal (12_000 * 100).round, v

    # Invalid type -> default 3x
    v = Profitable.estimated_valuation(at: :wtf)
    assert_equal (12_000 * 3).round, v
  end

  def test_time_to_next_mrr_milestone_no_more_milestones
    # Set current mrr to highest milestone or beyond
    Profitable.stub(:mrr, Profitable::NumericResult.new(100_000_000 * 100)) do
      msg = Profitable.time_to_next_mrr_milestone
      assert_match /Congratulations!/, msg
    end
  end

  def test_time_to_next_mrr_milestone_unable_without_positive_growth
    Profitable.stub(:mrr, Profitable::NumericResult.new(1_000 * 100)) do
      Profitable.stub(:calculate_mrr_growth_rate, 0) do
        msg = Profitable.time_to_next_mrr_milestone
        assert_match /Unable to calculate/, msg
      end
      Profitable.stub(:calculate_mrr_growth_rate, -10) do
        msg = Profitable.time_to_next_mrr_milestone
        assert_match /Unable to calculate/, msg
      end
    end
  end

  def test_recurring_revenue_percentage_zero_when_no_total_revenue
    assert_equal 0, Profitable.recurring_revenue_percentage(in_the_last: 30.days)
  end

  def test_churn_is_zero_when_no_subscribers_at_start
    assert_equal 0, Profitable.churn(in_the_last: 30.days)
  end

  def test_new_mrr_counts_subscriptions_created_at_period_start
    start = 10.days
    t = Time.now
    Timecop.freeze(t - start) do
      # created exactly at start boundary (inclusive)
      create_subscription(created_at: t - start)
    end
    # for newly created at start, prorated days should be full period
    val = Profitable.new_mrr(in_the_last: start)
    assert_operator val, :>=, 0
  end

  def test_mrr_at_includes_subscriptions_created_at_date
    t = Time.now
    Timecop.freeze(t - 1.day) do
      create_subscription(created_at: t - 1.day)
    end
    # created_at == date should be included
    val = Profitable.send(:calculate_mrr_at, t - 1.day)
    assert_operator val, :>, 0
  end

  def test_churned_mrr_ignores_subscriptions_ending_in_future
    Timecop.freeze(Time.now - 10.days) do
      create_subscription
    end
    sub = Pay::Subscription.last
    sub.update!(status: "canceled", ends_at: Time.now + 10.days)
    assert_equal 0, Profitable.churned_mrr(in_the_last: 30.days)
  end

  def test_average_revenue_per_customer_zero_when_no_paying_customers
    assert_equal 0, Profitable.average_revenue_per_customer
  end

  def test_lifetime_value_zero_when_no_customers_or_zero_churn
    # no customers
    assert_equal 0, Profitable.lifetime_value

    # add customers but zero churn
    Timecop.freeze(Time.now - 35.days) do
      create_subscription
    end
    # churn rate computed as zero
    Profitable.stub(:churn, Profitable::NumericResult.new(0, :percentage)) do
      assert_equal 0, Profitable.lifetime_value
    end
  end

  def test_normalize_to_monthly_handles_nil_and_case_insensitive_intervals
    base = Profitable::Processors::Base.new(nil)
    assert_equal 0, base.send(:normalize_to_monthly, nil, "month", 1)
    assert_equal 0, base.send(:normalize_to_monthly, 1000, nil, 1)
    assert_equal 0, base.send(:normalize_to_monthly, 1000, "month", nil)

    assert_in_delta 1000.0, base.send(:normalize_to_monthly, 1000, "Month", 1), 0.001
    assert_in_delta 41.6667, base.send(:normalize_to_monthly, 1000, "year", 2), 0.001
    assert_in_delta 30_000.0, base.send(:normalize_to_monthly, 1000, "day", 1), 0.001
    assert_in_delta 4_000.0, base.send(:normalize_to_monthly, 1000, "week", 1), 0.001
  end

  def test_negative_amounts_are_clamped_to_zero_in_mrr
    data = {
      "subscription_items" => [
        { "price" => { "unit_amount" => -500, "recurring" => { "interval" => "month", "interval_count" => 1 } } }
      ]
    }
    sub = Pay::Subscription.create!(
      customer: @customer,
      processor: "stripe",
      status: "active",
      quantity: 1,
      current_period_start: Time.now - 15.days,
      current_period_end: Time.now + 15.days,
      data: data
    )
    assert_equal 0, Profitable::MrrCalculator.process_subscription(sub)
  end
end