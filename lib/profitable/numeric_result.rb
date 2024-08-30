module Profitable
  class NumericResult < SimpleDelegator
    include ActionView::Helpers::NumberHelper

    def to_readable(precision = 2)
      "$#{price_in_cents_to_string(self, precision)}"
    end

    private

    def price_in_cents_to_string(price, precision = 2)
      number_with_delimiter(
        number_with_precision(
          (price.to_f / 100), precision: precision
        )
      ).to_s.sub(/\.?0+$/, '')
    end
  end
end
