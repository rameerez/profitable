module Profitable
  class NumericResult < SimpleDelegator
    include ActionView::Helpers::NumberHelper

    def initialize(value, type = :currency)
      super(value)
      @type = type
    end

    def to_readable(precision = 0)
      case @type
      when :currency
        "$#{price_in_cents_to_string(self, precision)}"
      when :percentage
        "#{number_with_precision(self, precision: precision)}%"
      else
        to_s
      end
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
