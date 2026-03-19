# frozen_string_literal: true

module Profitable
  # Pay exposes some processor-specific status variants beyond the core generic list.
  # We normalize them into business-meaningful groups so current-state metrics,
  # historical event metrics, and churn denominators all behave consistently.
  TRIAL_SUBSCRIPTION_STATUSES = ['trialing', 'on_trial'].freeze
  CHURNED_STATUSES  = ['canceled', 'cancelled', 'ended', 'deleted'].freeze
  NEVER_BILLABLE_SUBSCRIPTION_STATUSES = ['incomplete', 'incomplete_expired', 'unpaid'].freeze

  class << self
    include ActionView::Helpers::NumberHelper
    include Profitable::JsonHelpers

    DEFAULT_PERIOD = 30.days
    MRR_MILESTONES = [5, 10, 20, 30, 50, 75, 100, 200, 300, 400, 500, 1_000, 2_000, 3_000, 5_000, 10_000, 20_000, 30_000, 50_000, 83_333, 100_000, 250_000, 500_000, 1_000_000, 5_000_000, 10_000_000, 25_000_000, 50_000_000, 75_000_000, 100_000_000]

    # Monthly Recurring Revenue (MRR) from subscriptions that are billable right now.
    # This is a current recurring run-rate metric, useful for operating momentum
    # and near-term subscription changes.
    def mrr
      NumericResult.new(MrrCalculator.calculate)
    end

    # Annual Recurring Revenue (ARR) based on the current recurring base.
    # This is today's MRR annualized, not historical 12-month revenue.
    def arr
      NumericResult.new(calculate_arr)
    end

    def churn(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_churn(in_the_last), :percentage)
    end

    def all_time_revenue
      NumericResult.new(calculate_all_time_revenue)
    end

    # Trailing twelve-month revenue reflects actual cash collected in the last year.
    # It complements ARR, which annualizes the current recurring base.
    def ttm_revenue
      revenue_in_period(in_the_last: 12.months)
    end

    # Founder-friendly shorthand for trailing-twelve-month revenue.
    # We keep the explicit ttm_revenue name as the canonical API because bare
    # "TTM" is ambiguous in finance once profit metrics enter the picture.
    def ttm
      ttm_revenue
    end

    # Historical revenue collected over a rolling period.
    # Unlike ARR, this is trailing actual revenue rather than a projection.
    def revenue_in_period(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_revenue_in_period(in_the_last))
    end

    def recurring_revenue_in_period(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_recurring_revenue_in_period(in_the_last))
    end

    def recurring_revenue_percentage(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_recurring_revenue_percentage(in_the_last), :percentage)
    end

    def revenue_run_rate(in_the_last: 30.days)
      NumericResult.new(calculate_revenue_run_rate(in_the_last))
    end

    # Backwards-compatible ARR-multiple heuristic for a quick valuation estimate.
    # This is intentionally simple and should not be treated as a market appraisal.
    def estimated_valuation(multiplier = nil, at: nil, multiple: nil)
      estimated_arr_valuation(multiplier, at:, multiple:)
    end

    def estimated_arr_valuation(multiplier = nil, at: nil, multiple: nil)
      actual_multiplier = multiplier || at || multiple || 3
      NumericResult.new(calculate_estimated_valuation_from(arr.to_i, actual_multiplier))
    end

    def estimated_ttm_revenue_valuation(multiplier = nil, at: nil, multiple: nil)
      actual_multiplier = multiplier || at || multiple || 3
      NumericResult.new(calculate_estimated_valuation_from(ttm_revenue.to_i, actual_multiplier))
    end

    def estimated_revenue_run_rate_valuation(multiplier = nil, at: nil, multiple: nil, in_the_last: 30.days)
      actual_multiplier = multiplier || at || multiple || 3
      NumericResult.new(calculate_estimated_valuation_from(revenue_run_rate(in_the_last:).to_i, actual_multiplier))
    end

    # Customers who have actually monetized: either a paid charge or a subscription
    # that has crossed into a billable state.
    def total_customers
      NumericResult.new(calculate_total_customers, :integer)
    end

    # Customers who have ever had a paid subscription. Trial-only subscriptions do not count.
    def total_subscribers
      NumericResult.new(calculate_total_subscribers, :integer)
    end

    # Customers with subscriptions that are billable right now.
    # Excludes free trials, paused subscriptions, and churned subscriptions.
    def active_subscribers
      NumericResult.new(calculate_active_subscribers, :integer)
    end

    # First-time customers added in the period, based on first monetization date
    # rather than signup date.
    def new_customers(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_new_customers(in_the_last), :integer)
    end

    # Customers whose subscriptions first became billable in the period.
    # Trial starts do not count until the trial ends.
    def new_subscribers(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_new_subscribers(in_the_last), :integer)
    end

    def churned_customers(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_churned_customers(in_the_last), :integer)
    end

    # Full monthly value of subscriptions that became billable in the period.
    # This is a flow metric, so it still counts subscriptions that churned later in the same window.
    def new_mrr(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_new_mrr(in_the_last))
    end

    def churned_mrr(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_churned_mrr(in_the_last))
    end

    def average_revenue_per_customer
      NumericResult.new(calculate_average_revenue_per_customer)
    end

    def lifetime_value
      NumericResult.new(calculate_lifetime_value)
    end

    def mrr_growth(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_mrr_growth(in_the_last))
    end

    def mrr_growth_rate(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_mrr_growth_rate(in_the_last), :percentage)
    end

    def time_to_next_mrr_milestone
      current_mrr = (mrr.to_i) / 100  # Convert cents to dollars
      return "Unable to calculate. No MRR yet." if current_mrr <= 0

      next_milestone = MRR_MILESTONES.find { |milestone| milestone > current_mrr }
      return "Congratulations! You've reached the highest milestone." unless next_milestone

      monthly_growth_rate = calculate_mrr_growth_rate / 100
      return "Unable to calculate. Need more data or positive growth." if monthly_growth_rate <= 0

      # Convert monthly growth rate to daily growth rate
      daily_growth_rate = (1 + monthly_growth_rate) ** (1.0 / 30) - 1
      return "Unable to calculate. Growth rate too small." if daily_growth_rate <= 0

      # Calculate the number of days to reach the next milestone
      days_to_milestone = (Math.log(next_milestone.to_f / current_mrr) / Math.log(1 + daily_growth_rate)).ceil

      target_date = Time.current + days_to_milestone.days

      "#{days_to_milestone} days left to $#{number_with_delimiter(next_milestone)} MRR (#{target_date.strftime('%b %d, %Y')})"
    end

    def monthly_summary(months: 12)
      calculate_monthly_summary(months)
    end

    def daily_summary(days: 30)
      calculate_daily_summary(days)
    end

    def period_data(in_the_last: DEFAULT_PERIOD)
      calculate_period_data(in_the_last)
    end

    private

    # Helper to load subscriptions with processor info from customer
    def subscriptions_with_processor(scope = Pay::Subscription.all)
      scope
        .includes(:customer)
        .select('pay_subscriptions.*, pay_customers.processor as customer_processor')
        .joins(:customer)
    end

    # Business semantics: a subscription becomes "real" for subscriber / new MRR
    # reporting when billing starts. For trialless subscriptions that is created_at;
    # for trials it is trial_ends_at.
    def subscription_became_billable_at_sql
      'COALESCE(pay_subscriptions.trial_ends_at, pay_subscriptions.created_at)'
    end

    # We intentionally do not reuse Pay::Subscription.active here.
    # Pay's active scope is access-oriented and can include free-trial access,
    # while profitable needs billable subscription semantics for metrics.
    def subscription_is_billable_by(date, scope = Pay::Subscription.all)
      scope
        .where.not(status: NEVER_BILLABLE_SUBSCRIPTION_STATUSES)
        .where(
          "(pay_subscriptions.status NOT IN (?) OR (pay_subscriptions.trial_ends_at IS NOT NULL AND pay_subscriptions.trial_ends_at <= ?))",
          TRIAL_SUBSCRIPTION_STATUSES,
          date
        )
        .where(
          "(pay_subscriptions.status NOT IN (?) OR pay_subscriptions.ends_at IS NOT NULL)",
          CHURNED_STATUSES
        )
        .where(
          "(pay_subscriptions.status != ? OR pay_subscriptions.pause_starts_at IS NOT NULL)",
          'paused'
        )
    end

    # Any subscription that has ever crossed into a paid/billable state,
    # even if it later churned. This is used for "ever" style counts.
    def ever_billable_subscription_scope(scope = Pay::Subscription.all)
      subscription_is_billable_by(Time.current, scope)
        .where("#{subscription_became_billable_at_sql} <= ?", Time.current)
    end

    # Subscriptions that were billable at a historical point in time.
    # This powers MRR snapshots, churn denominators, and other period math.
    def billable_subscription_scope_at(date, scope = Pay::Subscription.all)
      subscription_is_billable_by(date, scope)
        .where("#{subscription_became_billable_at_sql} <= ?", date)
        .where('pay_subscriptions.ends_at IS NULL OR pay_subscriptions.ends_at > ?', date)
        .where('pay_subscriptions.pause_starts_at IS NULL OR pay_subscriptions.pause_starts_at > ?', date)
    end

    # Current billable subscriptions. A future ends_at or future pause start means
    # the subscription is still billable today and should remain in MRR / ARR.
    def current_billable_subscription_scope(scope = Pay::Subscription.all)
      billable_subscription_scope_at(Time.current, scope)
    end

    # Historical "new subscriber" / "new MRR" event window.
    # The event date is when billing starts, not when the subscription record is created.
    def billable_subscription_events_in_period(period_start, period_end, scope = Pay::Subscription.all)
      subscription_is_billable_by(period_end, scope)
        .where("#{subscription_became_billable_at_sql} BETWEEN ? AND ?", period_start, period_end)
    end

    def subscription_became_billable_at(subscription)
      subscription.trial_ends_at || subscription.created_at
    end

    def paid_charges
      # Pay gem v10+ stores charge data in `object` column, older versions used `data`
      # We check both columns for backwards compatibility using database-agnostic JSON extraction
      #
      # Performance note: The COALESCE pattern may prevent index usage on some databases.
      # This is an acceptable tradeoff for backwards compatibility with Pay < 10.
      # For high-volume scenarios, consider adding a composite index or upgrading to Pay 10+
      # where only the `object` column is used.

      # Build JSON extraction SQL for both object and data columns
      paid_object = json_extract('pay_charges.object', 'paid')
      paid_data = json_extract('pay_charges.data', 'paid')
      status_object = json_extract('pay_charges.object', 'status')
      status_data = json_extract('pay_charges.data', 'status')

      Pay::Charge
        .where("pay_charges.amount > 0")
        .where(<<~SQL.squish, 'false', 'succeeded')
          (
            (COALESCE(#{paid_object}, #{paid_data}) IS NULL
             OR COALESCE(#{paid_object}, #{paid_data}) != ?)
          )
          AND
          (
            COALESCE(#{status_object}, #{status_data}) = ?
            OR COALESCE(#{status_object}, #{status_data}) IS NULL
          )
        SQL
    end

    # Revenue metrics should reflect net cash collected, not gross billed amounts.
    # When Pay stores refunded cents on the charge, subtract them from revenue.
    def net_revenue(scope)
      scope.sum(net_charge_amount_sql)
    end

    def net_charge_amount_sql
      "pay_charges.amount - COALESCE(pay_charges.amount_refunded, 0)"
    end

    def calculate_all_time_revenue
      net_revenue(paid_charges)
    end

    def calculate_arr
      (mrr.to_f * 12).round
    end

    def calculate_estimated_valuation(multiplier = 3)
      calculate_estimated_valuation_from(calculate_arr, multiplier)
    end

    def calculate_estimated_valuation_from(base_amount, multiplier = 3)
      multiplier = parse_multiplier(multiplier)
      (base_amount * multiplier).round
    end

    def parse_multiplier(input)
      case input
      when Numeric
        input.to_f
      when String
        if input.end_with?('x')
          input.chomp('x').to_f
        else
          input.to_f
        end
      else
        3.0 # Default multiplier if input is invalid
      end.clamp(0.1, 100) # Ensure multiplier is within a reasonable range
    end

    def calculate_churn(period = DEFAULT_PERIOD)
      calculate_churn_rate_for_period(period.ago, Time.current)
    end

    def calculate_churned_customers(period = DEFAULT_PERIOD)
      calculate_churned_subscribers_in_period(period.ago, Time.current)
    end

    def calculate_churned_mrr(period = DEFAULT_PERIOD)
      calculate_churned_mrr_in_period(period.ago, Time.current)
    end

    def calculate_new_mrr(period = DEFAULT_PERIOD)
      calculate_new_mrr_in_period(period.ago, Time.current)
    end

    def calculate_revenue_in_period(period)
      net_revenue(paid_charges.where(created_at: period.ago..Time.current))
    end

    def calculate_revenue_run_rate(period)
      return 0 if period.to_i <= 0

      # TrustMRR-style revenue multiples are usually quoted against recent monthly
      # revenue annualized, so we normalize to a 30-day month and multiply by 12.
      monthly_revenue = calculate_revenue_in_period(period).to_f * (30.days.to_f / period.to_f)
      (monthly_revenue * 12).round
    end

    def calculate_recurring_revenue_in_period(period)
      net_revenue(
        paid_charges
          .joins('INNER JOIN pay_subscriptions ON pay_charges.subscription_id = pay_subscriptions.id')
          .where(created_at: period.ago..Time.current)
      )
    end

    def calculate_recurring_revenue_percentage(period)
      total_revenue = calculate_revenue_in_period(period)
      recurring_revenue = calculate_recurring_revenue_in_period(period)

      return 0 if total_revenue.zero?

      ((recurring_revenue.to_f / total_revenue) * 100).round(2)
    end

    def calculate_total_customers
      actual_customers.count
    end

    def calculate_total_subscribers
      ever_billable_subscription_scope.distinct.count(:customer_id)
    end

    def calculate_active_subscribers
      current_billable_subscription_scope.distinct.count(:customer_id)
    end

    def actual_customers
      # A "customer" here means a monetized customer, not just an account record.
      # We therefore union paid one-off/charge customers with customers whose
      # subscriptions have reached a billable state.
      customers_with_paid_charges = Pay::Customer.where(id: paid_charges.select(:customer_id))
      customers_with_billable_subscriptions = Pay::Customer.where(id: ever_billable_subscription_scope.select(:customer_id))

      customers_with_paid_charges.or(customers_with_billable_subscriptions).distinct
    end

    def calculate_new_customers(period)
      period_start = period.ago
      period_end = Time.current

      # "New customer" is defined by first monetization date.
      # We intentionally do not use Pay::Customer.created_at because a user might
      # sign up long before they ever pay or convert from trial.
      first_charge_dates = paid_charges.group(:customer_id).minimum(:created_at)
      first_subscription_dates = ever_billable_subscription_scope
        .group(:customer_id)
        .minimum(Arel.sql(subscription_became_billable_at_sql))

      customer_ids = first_charge_dates.keys | first_subscription_dates.keys

      customer_ids.count do |customer_id|
        first_customer_date = [first_charge_dates[customer_id], first_subscription_dates[customer_id]].compact.min
        first_customer_date && first_customer_date >= period_start && first_customer_date <= period_end
      end
    end

    def calculate_new_subscribers(period)
      calculate_new_subscribers_in_period(period.ago, Time.current)
    end

    def calculate_average_revenue_per_customer
      paying_customers = calculate_total_customers
      return 0 if paying_customers.zero?
      (all_time_revenue.to_f / paying_customers).round
    end

    def calculate_lifetime_value
      # LTV = Monthly ARPU / Monthly Churn Rate
      # where ARPU (Average Revenue Per User) = MRR / active subscribers
      subscribers = calculate_active_subscribers
      return 0 if subscribers.zero?

      monthly_arpu = mrr.to_f / subscribers  # in cents
      churn_rate = churn.to_f / 100  # monthly churn as decimal (e.g., 5% = 0.05)
      return 0 if churn_rate.zero?

      (monthly_arpu / churn_rate).round  # LTV in cents
    end

    def calculate_mrr_growth(period = DEFAULT_PERIOD)
      new_mrr = calculate_new_mrr(period)
      churned_mrr = calculate_churned_mrr(period)
      new_mrr - churned_mrr
    end

    def calculate_mrr_growth_rate(period = DEFAULT_PERIOD)
      end_date = Time.current
      start_date = end_date - period

      start_mrr = calculate_mrr_at(start_date)
      end_mrr = calculate_mrr_at(end_date)

      return 0 if start_mrr == 0
      ((end_mrr.to_f - start_mrr) / start_mrr * 100).round(2)
    end

    def calculate_mrr_at(date)
      # Find subscriptions that were active AT the given date:
      # - Started billing before or on that date
      # - Not ended before that date (ends_at is nil OR ends_at > date)
      # - Not paused at that date
      # - Not still in a free trial at that date
      subscriptions_with_processor(
        billable_subscription_scope_at(date)
      ).sum do |subscription|
        MrrCalculator.process_subscription(subscription)
      end
    end

    def calculate_period_data(period)
      period_start = period.ago
      period_end = Time.current

      # Keep these values delegated to the same underlying helpers used by the
      # public methods so the dashboard and direct API calls stay in lockstep.
      new_customers_count = calculate_new_customers(period)
      churned_count = calculate_churned_subscribers_in_period(period_start, period_end)
      new_mrr_val = calculate_new_mrr_in_period(period_start, period_end)
      churned_mrr_val = calculate_churned_mrr_in_period(period_start, period_end)
      revenue_val = net_revenue(paid_charges.where(created_at: period_start..period_end))

      # Churn rate (reuses churned_count)
      total_at_start = billable_subscription_scope_at(period_start)
        .distinct
        .count('customer_id')
      churn_rate = total_at_start > 0 ? (churned_count.to_f / total_at_start * 100).round(1) : 0

      {
        new_customers: NumericResult.new(new_customers_count, :integer),
        churned_customers: NumericResult.new(churned_count, :integer),
        churn: NumericResult.new(churn_rate, :percentage),
        new_mrr: NumericResult.new(new_mrr_val),
        churned_mrr: NumericResult.new(churned_mrr_val),
        mrr_growth: NumericResult.new(new_mrr_val - churned_mrr_val),
        revenue: NumericResult.new(revenue_val)
      }
    end

    # Batched: loads all data in 5 queries then groups by month in Ruby
    def calculate_monthly_summary(months_count)
      overall_start = (months_count - 1).months.ago.beginning_of_month
      overall_end = Time.current.end_of_month

      # Bulk load all data for the full range, then group in Ruby.
      # This keeps the dashboard query count low while preserving the same
      # billable-date semantics used by the single-metric helpers.
      new_sub_records = Pay::Subscription
        .merge(billable_subscription_events_in_period(overall_start, overall_end))
        .pluck(:customer_id, Arel.sql(subscription_became_billable_at_sql))

      churned_sub_records = Pay::Subscription
        .where(status: CHURNED_STATUSES)
        .where(ends_at: overall_start..overall_end)
        .pluck(:customer_id, :ends_at)

      new_mrr_subs = subscriptions_with_processor(
        billable_subscription_events_in_period(overall_start, overall_end)
      ).to_a

      churned_mrr_subs = subscriptions_with_processor(
        Pay::Subscription
          .where(status: CHURNED_STATUSES)
          .where(ends_at: overall_start..overall_end)
      ).to_a

      churn_base_records = billable_subscription_scope_at(overall_end, Pay::Subscription)
        .where('pay_subscriptions.ends_at IS NULL OR pay_subscriptions.ends_at > ?', overall_start)
        .pluck(:customer_id, Arel.sql(subscription_became_billable_at_sql), :ends_at)

      # Group by month in Ruby using billable-at and ends_at as the event dates,
      # rather than raw subscription created_at.
      summary = []
      (months_count - 1).downto(0) do |months_ago|
        month_start = months_ago.months.ago.beginning_of_month
        month_end = month_start.end_of_month

        new_count = new_sub_records
          .select { |_, created_at| created_at >= month_start && created_at <= month_end }
          .map(&:first).uniq.count

        churned_count = churned_sub_records
          .select { |_, ends_at| ends_at >= month_start && ends_at <= month_end }
          .map(&:first).uniq.count

        new_mrr_amount = new_mrr_subs
          .select { |s| subscription_became_billable_at(s) >= month_start && subscription_became_billable_at(s) <= month_end }
          .sum { |s| MrrCalculator.process_subscription(s) }

        churned_mrr_amount = churned_mrr_subs
          .select { |s| s.ends_at >= month_start && s.ends_at <= month_end }
          .sum { |s| MrrCalculator.process_subscription(s) }

        total_at_start = churn_base_records
          .select { |_, billable_at, ends_at| billable_at < month_start && (ends_at.nil? || ends_at > month_start) }
          .map(&:first).uniq.count

        churn_rate = total_at_start > 0 ? (churned_count.to_f / total_at_start * 100).round(1) : 0

        summary << {
          month: month_start.strftime('%Y-%m'),
          month_date: month_start,
          new_subscribers: new_count,
          churned_subscribers: churned_count,
          net_subscribers: new_count - churned_count,
          new_mrr: new_mrr_amount,
          churned_mrr: churned_mrr_amount,
          net_mrr: new_mrr_amount - churned_mrr_amount,
          churn_rate: churn_rate
        }
      end

      summary
    end

    # Batched: loads all data in 2 queries then groups by day in Ruby
    def calculate_daily_summary(days_count)
      overall_start = (days_count - 1).days.ago.beginning_of_day
      overall_end = Time.current.end_of_day

      # Daily summary intentionally uses the same "became billable" event date as
      # new_subscribers/new_mrr, so trial starts do not appear as paid conversions.
      new_sub_records = Pay::Subscription
        .merge(billable_subscription_events_in_period(overall_start, overall_end))
        .pluck(:customer_id, Arel.sql(subscription_became_billable_at_sql))

      churned_sub_records = Pay::Subscription
        .where(status: CHURNED_STATUSES)
        .where(ends_at: overall_start..overall_end)
        .pluck(:customer_id, :ends_at)

      summary = []
      (days_count - 1).downto(0) do |days_ago|
        day_start = days_ago.days.ago.beginning_of_day
        day_end = day_start.end_of_day

        new_count = new_sub_records
          .select { |_, created_at| created_at >= day_start && created_at <= day_end }
          .map(&:first).uniq.count

        churned_count = churned_sub_records
          .select { |_, ends_at| ends_at >= day_start && ends_at <= day_end }
          .map(&:first).uniq.count

        summary << {
          date: day_start.to_date,
          new_subscribers: new_count,
          churned_subscribers: churned_count
        }
      end

      summary
    end

    # Consolidated methods that work with any date range
    def calculate_new_subscribers_in_period(period_start, period_end)
      billable_subscription_events_in_period(period_start, period_end)
        .distinct
        .count(:customer_id)
    end

    def calculate_churned_subscribers_in_period(period_start, period_end)
      # Churn happens when access/billing actually ends, which Pay stores on ends_at.
      Pay::Subscription
        .where(status: CHURNED_STATUSES)
        .where(ends_at: period_start..period_end)
        .distinct
        .count('customer_id')
    end

    def calculate_new_mrr_in_period(period_start, period_end)
      # New MRR is the full fixed monthly value of subscriptions whose billing
      # started in the window. It is not prorated, and it still counts if the
      # subscription churns later in the same period.
      subscriptions_with_processor(
        billable_subscription_events_in_period(period_start, period_end)
      ).sum do |subscription|
        MrrCalculator.process_subscription(subscription)
      end
    end

    def calculate_churned_mrr_in_period(period_start, period_end)
      # Churned MRR is the full fixed monthly value being lost at churn time.
      subscriptions_with_processor(
        Pay::Subscription
          .where(status: CHURNED_STATUSES)
          .where(ends_at: period_start..period_end)
      ).sum do |subscription|
        MrrCalculator.process_subscription(subscription)
      end
    end

    def calculate_churn_rate_for_period(period_start, period_end)
      # Count subscribers who were billable at the start of the period.
      # This keeps free trials and not-yet-paying subscriptions out of the denominator.
      total_subscribers_start = billable_subscription_scope_at(period_start)
        .distinct
        .count('customer_id')

      churned = calculate_churned_subscribers_in_period(period_start, period_end)
      return 0 if total_subscribers_start == 0

      (churned.to_f / total_subscribers_start * 100).round(1)
    end

  end
end
