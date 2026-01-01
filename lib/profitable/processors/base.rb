module Profitable
  module Processors
    class Base
      attr_reader :subscription

      def initialize(subscription)
        @subscription = subscription
      end

      def calculate_mrr
        0
      end

      protected

      # Pay gem v10+ stores Stripe objects in the `object` column,
      # while older versions used `data`. This method provides backwards compatibility.
      def subscription_data
        subscription.try(:object) || subscription.try(:data)
      end

      def normalize_to_monthly(amount, interval, interval_count)
        return 0 if amount.nil? || interval.nil? || interval_count.nil?

        # Ensure interval_count is converted to integer before division
        interval_count_int = interval_count.to_i
        return 0 if interval_count_int.zero?

        monthly_amount = case interval.to_s.downcase
        when 'day'
          amount.to_f * 30 / interval_count_int
        when 'week'
          amount.to_f * 4 / interval_count_int
        when 'month'
          amount.to_f / interval_count_int
        when 'year'
          amount.to_f / (12 * interval_count_int)
        else
          Rails.logger.warn("Unknown interval for MRR calculation: #{interval}")
          0
        end

        monthly_amount.round  # Always return integer cents
      end
    end
  end
end
