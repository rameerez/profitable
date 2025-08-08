# frozen_string_literal: true
require "test_helper"

class NumericResultTest < Minitest::Test
  def test_currency_default_and_precision_behavior
    result = Profitable::NumericResult.new(123_456)
    assert_equal "$1,235", result.to_readable
    assert_equal "$1,234.56", result.to_readable(2)

    zero = Profitable::NumericResult.new(0)
    assert_equal "$0", zero.to_readable
    assert_equal "$0", zero.to_readable(2)

    trailing_zero = Profitable::NumericResult.new(100_000)
    assert_equal "$1,000", trailing_zero.to_readable(2)
  end

  def test_percentage_formatting
    result = Profitable::NumericResult.new(12.3456, :percentage)
    assert_equal "12%", result.to_readable
    assert_equal "12.35%", result.to_readable(2)
  end

  def test_integer_formatting
    result = Profitable::NumericResult.new(12_345, :integer)
    assert_equal "12,345", result.to_readable
  end

  def test_string_passthrough
    result = Profitable::NumericResult.new("hello", :string)
    assert_equal "hello", result.to_readable
  end

  def test_unknown_type_falls_back_to_to_s
    obj = Object.new
    def obj.to_s; "xyz"; end
    result = Profitable::NumericResult.new(obj, :unknown)
    assert_equal "xyz", result.to_readable
  end
end