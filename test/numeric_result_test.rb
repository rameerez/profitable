# frozen_string_literal: true

require "test_helper"

class NumericResultTest < Minitest::Test
  # ============================================================================
  # BASIC FUNCTIONALITY
  # ============================================================================

  def test_delegates_to_underlying_value
    result = Profitable::NumericResult.new(1000)

    assert_equal 1000, result.to_i
    assert_equal 1000.0, result.to_f
    assert_equal "1000", result.to_s
  end

  def test_responds_to_numeric_methods
    result = Profitable::NumericResult.new(1000)

    assert result.respond_to?(:+)
    assert result.respond_to?(:-)
    assert result.respond_to?(:*)
    assert result.respond_to?(:/)
  end

  def test_arithmetic_operations
    result = Profitable::NumericResult.new(1000)

    assert_equal 1500, result + 500
    assert_equal 500, result - 500
    assert_equal 2000, result * 2
    assert_equal 500, result / 2
  end

  # ============================================================================
  # CURRENCY TYPE (default)
  # ============================================================================

  def test_currency_to_readable_converts_cents_to_dollars
    # 1000 cents = $10.00
    result = Profitable::NumericResult.new(1000)

    assert_equal "$10", result.to_readable(0)
  end

  def test_currency_to_readable_with_precision
    result = Profitable::NumericResult.new(1050)

    assert_equal "$10.5", result.to_readable(2)  # Trailing zeros stripped
  end

  def test_currency_to_readable_large_amounts
    # $1,234,567.89 in cents
    result = Profitable::NumericResult.new(123_456_789)

    assert_equal "$1,234,568", result.to_readable(0)
  end

  def test_currency_zero_value
    result = Profitable::NumericResult.new(0)

    assert_equal "$0", result.to_readable(0)
    assert_equal "$0", result.to_readable(2)
  end

  def test_currency_small_values
    result = Profitable::NumericResult.new(99)  # 99 cents

    assert_equal "$1", result.to_readable(0)  # Rounds to $1
    assert_equal "$0.99", result.to_readable(2)
  end

  def test_currency_negative_values
    result = Profitable::NumericResult.new(-5000)  # -$50

    assert_equal "$-50", result.to_readable(0)
  end

  # ============================================================================
  # PERCENTAGE TYPE
  # ============================================================================

  def test_percentage_to_readable
    result = Profitable::NumericResult.new(5.25, :percentage)

    assert_equal "5.25%", result.to_readable(2)
  end

  def test_percentage_to_readable_whole_number
    result = Profitable::NumericResult.new(10, :percentage)

    assert_equal "10%", result.to_readable(0)
  end

  def test_percentage_to_readable_zero
    result = Profitable::NumericResult.new(0, :percentage)

    assert_equal "0%", result.to_readable(0)
  end

  def test_percentage_to_readable_small_decimal
    result = Profitable::NumericResult.new(0.5, :percentage)

    assert_equal "0.5%", result.to_readable(1)
  end

  def test_percentage_to_readable_large_value
    result = Profitable::NumericResult.new(150.75, :percentage)

    assert_equal "150.75%", result.to_readable(2)
  end

  # ============================================================================
  # INTEGER TYPE
  # ============================================================================

  def test_integer_to_readable
    result = Profitable::NumericResult.new(1234, :integer)

    assert_equal "1,234", result.to_readable
  end

  def test_integer_to_readable_small_value
    result = Profitable::NumericResult.new(5, :integer)

    assert_equal "5", result.to_readable
  end

  def test_integer_to_readable_large_value
    result = Profitable::NumericResult.new(1_234_567_890, :integer)

    assert_equal "1,234,567,890", result.to_readable
  end

  def test_integer_to_readable_zero
    result = Profitable::NumericResult.new(0, :integer)

    assert_equal "0", result.to_readable
  end

  # ============================================================================
  # STRING TYPE
  # ============================================================================

  def test_string_to_readable
    result = Profitable::NumericResult.new(42, :string)

    assert_equal "42", result.to_readable
  end

  # ============================================================================
  # UNKNOWN TYPE (fallback)
  # ============================================================================

  def test_unknown_type_to_readable
    result = Profitable::NumericResult.new(999, :unknown_type)

    assert_equal "999", result.to_readable
  end

  # ============================================================================
  # EDGE CASES
  # ============================================================================

  def test_float_value
    result = Profitable::NumericResult.new(1234.56)

    assert_in_delta 1234.56, result.to_f, 0.001
  end

  def test_comparison_with_numeric
    result = Profitable::NumericResult.new(1000)

    assert result > 500
    assert result < 1500
    assert result == 1000
    assert result >= 1000
    assert result <= 1000
  end

  def test_comparison_with_another_numeric_result
    result1 = Profitable::NumericResult.new(1000)
    result2 = Profitable::NumericResult.new(2000)

    assert result2 > result1
  end

  def test_can_be_used_in_calculations
    mrr = Profitable::NumericResult.new(10000)  # $100 MRR
    arr = mrr * 12

    assert_equal 120000, arr
  end

  def test_truthiness
    zero_result = Profitable::NumericResult.new(0)
    positive_result = Profitable::NumericResult.new(100)

    assert_equal true, zero_result.zero?
    assert_equal false, positive_result.zero?
  end
end
