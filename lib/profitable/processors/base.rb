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

      def normalize_to_monthly(amount, interval, interval_count)
        return 0 if amount.nil? || interval.nil? || interval_count.nil?

        case interval.to_s.downcase
        when 'day'
          amount * 30.0 / interval_count
        when 'week'
          amount * 4.0 / interval_count
        when 'month'
          amount / interval_count
        when 'year'
          amount / (12.0 * interval_count)
        else
          Rails.logger.warn("Unknown interval for MRR calculation: #{interval}")
          0
        end
      end
    end
  end
end
