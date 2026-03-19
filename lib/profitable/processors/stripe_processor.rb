module Profitable
  module Processors
    class StripeProcessor < Base
      def calculate_mrr
        data = subscription_data
        return 0 if data.nil?

        # Pay gem v10+ stores items at object['items']['data']
        # Older versions stored at data['subscription_items']
        subscription_items = data.dig('items', 'data') || data['subscription_items']
        return 0 if subscription_items.nil? || subscription_items.empty?

        # Sum MRR from ALL subscription items (not just the first one)
        # Stripe subscriptions can have multiple line items
        total_mrr = 0

        subscription_items.each do |item|
          price_data = item['price'] || item
          next if price_data.nil?
          next if price_data.dig('recurring', 'usage_type') == 'metered'

          amount = price_data['unit_amount']
          next if amount.nil?

          # Each item can have its own quantity
          item_quantity = item['quantity'] || 1
          interval = price_data.dig('recurring', 'interval')
          interval_count = price_data.dig('recurring', 'interval_count') || 1

          total_mrr += normalize_to_monthly(amount * item_quantity, interval, interval_count)
        end

        total_mrr
      end
    end
  end
end
