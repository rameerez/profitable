# frozen_string_literal: true
require "test_helper"

class ProfitableModuleTest < Minitest::Test
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

  def create_charge(amount:, created_at: Time.now, data: {}, subscription: nil)
    Pay::Charge.create!(customer: @customer, amount: amount, created_at: created_at, updated_at: created_at, data: data, subscription_id: subscription&.id)
  end

  def test_arr_is_12_times_mrr
    create_subscription
    assert_equal(12 * 1000, Profitable.arr)
    assert_equal "$120", Profitable.arr.to_readable
  end

  def test_estimated_valuation_parsing
    create_subscription
    assert_equal 12_000 * 3, Profitable.estimated_valuation
    assert_equal 12_000 * 5, Profitable.estimated_valuation(5)
    assert_equal 12_000 * 4.5, Profitable.estimated_valuation(at: "4.5x")
    assert_equal 12_000 * 2.0, Profitable.estimated_valuation(multiple: "2")
  end

  def test_total_customers_counts_distinct_with_paid_charges
    create_charge(amount: 1000, data: { "status" => "succeeded", "paid" => true })
    create_charge(amount: 0, data: { "status" => "succeeded", "paid" => true })
    assert_equal 1, Profitable.total_customers
  end

  def test_paid_charges_scope_respects_paid_and_status
    # paid is true, status succeeded
    c1 = create_charge(amount: 1000, data: { "status" => "succeeded", "paid" => true })
    # paid string false should be excluded
    c2 = create_charge(amount: 500, data: { "status" => "succeeded", "paid" => "false" })
    # status failed excluded
    c3 = create_charge(amount: 700, data: { "status" => "failed", "paid" => true })

    total = Profitable.send(:paid_charges).sum(:amount)
    assert_equal 1000, total
    refute_includes Profitable.send(:paid_charges), c2
    refute_includes Profitable.send(:paid_charges), c3
  end

  def test_all_time_revenue_and_period_revenue
    t0 = Time.now - 10.days
    t1 = Time.now - 2.days
    create_charge(amount: 1000, created_at: t0, data: { "status" => "succeeded", "paid" => true })
    create_charge(amount: 2000, created_at: t1, data: { "status" => "succeeded", "paid" => true })

    assert_equal 3000, Profitable.all_time_revenue
    assert_equal 3000, Profitable.revenue_in_period(in_the_last: 30.days)
    assert_equal 2000, Profitable.revenue_in_period(in_the_last: 3.days)
    assert_equal "$20", Profitable.revenue_in_period(in_the_last: 3.days).to_readable
  end

  def test_recurring_revenue_and_percentage
    sub = create_subscription
    create_charge(amount: 1000, created_at: Time.now, data: { "status" => "succeeded", "paid" => true })
    create_charge(amount: 500, created_at: Time.now, data: { "status" => "succeeded", "paid" => true }, subscription: sub)

    total = Profitable.revenue_in_period(in_the_last: 30.days)
    recurring = Profitable.recurring_revenue_in_period(in_the_last: 30.days)
    assert_equal 1500, total
    assert_equal 500, recurring
    assert_equal 33.33, Profitable.recurring_revenue_percentage(in_the_last: 30.days)
    assert_equal "33.33%", Profitable.recurring_revenue_percentage(in_the_last: 30.days).to_readable(2)
  end

  def test_total_subscribers_active_and_new_subscribers
    # one subscriber on default customer
    create_subscription
    # ensure default customer is older than 1 day so not counted as "new"
    @customer.update_columns(created_at: Time.now - 2.days)
    # one subscriber on another customer
    other = nil
    Timecop.freeze(Time.now - 2.days) do
      other = Pay::Customer.create!(processor: "stripe")
      Pay::Subscription.create!(customer: other, processor: "stripe", status: "canceled", current_period_start: Time.now - 1.day, current_period_end: Time.now + 1.day, data: { "subscription_items" => [{ "price" => { "unit_amount" => 1000, "recurring" => { "interval" => "month", "interval_count" => 1 } } }] })
    end

    assert_equal 2, Profitable.total_subscribers
    assert_equal 1, Profitable.active_subscribers

    # create a new customer with subscription within the last day
    Timecop.freeze(Time.now - 12.hours) do
      recent = Pay::Customer.create!(processor: "stripe")
      Pay::Subscription.create!(customer: recent, processor: "stripe", status: "active", current_period_start: Time.now - 1.hour, current_period_end: Time.now + 29.days, data: { "subscription_items" => [{ "price" => { "unit_amount" => 1000, "recurring" => { "interval" => "month", "interval_count" => 1 } } }] })
    end
    assert_equal 1, Profitable.new_subscribers(in_the_last: 1.day)
  end

  def test_actual_customers_and_new_customers
    # two actual customers: one with charge, one with subscription
    create_charge(amount: 100, data: { "status" => "succeeded", "paid" => true })
    # make default customer older than 1 day so not counted as new
    @customer.update_columns(created_at: Time.now - 2.days)
    other = nil
    Timecop.freeze(Time.now - 2.days) do
      other = Pay::Customer.create!(processor: "stripe")
      Pay::Subscription.create!(customer: other, processor: "stripe", status: "active", current_period_start: Time.now - 1.day, current_period_end: Time.now + 1.day, data: { "subscription_items" => [{ "price" => { "unit_amount" => 1000, "recurring" => { "interval" => "month", "interval_count" => 1 } } }] })
    end

    assert_includes Profitable.send(:actual_customers), other

    # new customer created within last day with a charge
    Timecop.freeze(Time.now - 12.hours) do
      recent = Pay::Customer.create!(processor: "stripe")
      Pay::Charge.create!(customer: recent, amount: 200, created_at: Time.now, updated_at: Time.now, data: { "status" => "succeeded", "paid" => true })
    end
    assert_equal 1, Profitable.new_customers(in_the_last: 1.day)
  end

  def test_churn_and_churned_customers_and_mrr
    # Two active subscribers existed before the 30-day window
    s1 = nil
    s2 = nil
    Timecop.freeze(Time.now - 35.days) do
      s1 = create_subscription(status: "active")
      s2 = create_subscription(status: "active")
    end

    # churn one customer within last 30 days
    sub = s1
    sub.update!(status: "canceled", ends_at: Time.now - 1.day)

    assert_equal 1, Profitable.churned_customers(in_the_last: 30.days)
    # current implementation counts active subscribers at evaluation time for start baseline
    assert_equal 100.0, Profitable.churn(in_the_last: 30.days)

    # churned mrr proration where ends_at within period
    assert_operator Profitable.churned_mrr(in_the_last: 30.days), :>=, 0
  end

  def test_average_revenue_per_customer_and_ltv
    create_charge(amount: 1000, data: { "status" => "succeeded", "paid" => true })
    assert_equal 1000, Profitable.average_revenue_per_customer

    # Ensure non-zero churn: one active and one churned subscriber, both existing before window
    Timecop.freeze(Time.now - 35.days) do
      # active subscriber that remains active
      active_customer = Pay::Customer.create!(processor: "stripe")
      Pay::Subscription.create!(customer: active_customer, processor: "stripe", status: "active", current_period_start: Time.now - 1.day, current_period_end: Time.now + 29.days, data: { "subscription_items" => [{ "price" => { "unit_amount" => 1000, "recurring" => { "interval" => "month", "interval_count" => 1 } } }] })

      # subscriber that will churn within the window
      churn_customer = Pay::Customer.create!(processor: "stripe")
      @churn_sub = Pay::Subscription.create!(customer: churn_customer, processor: "stripe", status: "active", current_period_start: Time.now - 1.day, current_period_end: Time.now + 29.days, data: { "subscription_items" => [{ "price" => { "unit_amount" => 1000, "recurring" => { "interval" => "month", "interval_count" => 1 } } }] })
    end
    @churn_sub.update!(status: "canceled", ends_at: Time.now - 1.day)

    refute_equal 0, Profitable.lifetime_value
  end

  def test_mrr_growth_and_rate_and_milestone_text
    # Create baseline 30 days ago
    Timecop.freeze(Time.now - 30.days) do
      create_subscription
    end

    # Add new mrr in last period
    Timecop.freeze(Time.now - 5.days) do
      create_subscription
    end

    growth = Profitable.mrr_growth(in_the_last: 30.days)
    assert growth >= 0

    rate = Profitable.mrr_growth_rate(in_the_last: 30.days)
    assert rate >= 0

    text = Profitable.time_to_next_mrr_milestone
    assert text.is_a?(String)
  end

  def test_version_constant_exists
    assert_match /\d+\.\d+\.\d+/, Profitable::VERSION
  end
end