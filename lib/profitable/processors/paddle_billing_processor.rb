module Profitable
  module Processors
    class PaddleBillingProcessor < Base
      def calculate_mrr
        data = subscription_data
        return 0 if data.nil?

        items = data['items']
        return 0 if items.nil? || items.empty?

        # Sum MRR from ALL subscription items
        total_mrr = 0

        items.each do |item|
          price_data = item['price']
          next if price_data.nil?

          amount = price_data.dig('unit_price', 'amount')
          next if amount.nil?

          item_quantity = item['quantity'] || 1
          interval = price_data.dig('billing_cycle', 'interval')
          interval_count = price_data.dig('billing_cycle', 'frequency')

          total_mrr += normalize_to_monthly(amount * item_quantity, interval, interval_count)
        end

        total_mrr
      end
    end
  end
end
