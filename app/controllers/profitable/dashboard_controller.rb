module Profitable
  class DashboardController < BaseController
    def index
      @mrr = Profitable.mrr
      @mrr_growth_rate = Profitable.mrr_growth_rate
      @total_customers = Profitable.total_customers
      @all_time_revenue = Profitable.all_time_revenue
      @estimated_valuation = Profitable.estimated_valuation
      @average_revenue_per_customer = Profitable.average_revenue_per_customer
      @lifetime_value = Profitable.lifetime_value

      @show_milestone = @mrr_growth_rate > 0
      @milestone_message = Profitable.time_to_next_mrr_milestone if @show_milestone

      @monthly_summary = Profitable.monthly_summary(months: 12)
      @daily_summary = Profitable.daily_summary(days: 30)

      @periods = [24.hours, 7.days, 30.days]
      @period_data = @periods.each_with_object({}) do |period, hash|
        hash[period] = Profitable.period_data(in_the_last: period)
      end
    end
  end
end
