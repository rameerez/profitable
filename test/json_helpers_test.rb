# frozen_string_literal: true

require "test_helper"

class JsonHelpersTest < Minitest::Test
  # Create a test class that includes the JsonHelpers module
  class TestClass
    include Profitable::JsonHelpers
  end

  def setup
    @helper = TestClass.new
  end

  # ============================================================================
  # VALID INPUTS
  # ============================================================================

  def test_accepts_valid_table_column_format
    # Should not raise for valid table.column format
    result = @helper.json_extract('pay_charges.object', 'paid')
    refute_nil result
  end

  def test_accepts_valid_single_column_format
    result = @helper.json_extract('object', 'paid')
    refute_nil result
  end

  def test_accepts_valid_json_key
    result = @helper.json_extract('pay_charges.object', 'status')
    refute_nil result
  end

  def test_accepts_json_key_with_underscores
    result = @helper.json_extract('pay_charges.object', 'billing_period_unit')
    refute_nil result
  end

  def test_accepts_table_column_with_multiple_parts
    result = @helper.json_extract('schema.table.column', 'key')
    refute_nil result
  end

  # ============================================================================
  # SQL INJECTION PREVENTION - TABLE_COLUMN VALIDATION
  # ============================================================================

  def test_rejects_sql_injection_in_table_column_with_quotes
    assert_raises(ArgumentError) do
      @helper.json_extract("pay_charges.object'; DROP TABLE users; --", 'paid')
    end
  end

  def test_rejects_sql_injection_in_table_column_with_semicolon
    assert_raises(ArgumentError) do
      @helper.json_extract('pay_charges.object; DELETE FROM users', 'paid')
    end
  end

  def test_rejects_sql_injection_in_table_column_with_parentheses
    assert_raises(ArgumentError) do
      @helper.json_extract('pay_charges.object)', 'paid')
    end
  end

  def test_rejects_sql_injection_in_table_column_with_dash_dash
    assert_raises(ArgumentError) do
      @helper.json_extract('pay_charges.object --', 'paid')
    end
  end

  def test_rejects_table_column_starting_with_number
    assert_raises(ArgumentError) do
      @helper.json_extract('123table.column', 'paid')
    end
  end

  def test_rejects_empty_table_column
    assert_raises(ArgumentError) do
      @helper.json_extract('', 'paid')
    end
  end

  def test_rejects_nil_table_column
    assert_raises(ArgumentError) do
      @helper.json_extract(nil, 'paid')
    end
  end

  def test_rejects_table_column_with_spaces
    assert_raises(ArgumentError) do
      @helper.json_extract('pay charges.object', 'paid')
    end
  end

  # ============================================================================
  # SQL INJECTION PREVENTION - JSON_KEY VALIDATION
  # ============================================================================

  def test_rejects_sql_injection_in_json_key_with_quotes
    assert_raises(ArgumentError) do
      @helper.json_extract('pay_charges.object', "paid'; DROP TABLE users; --")
    end
  end

  def test_rejects_sql_injection_in_json_key_with_dollar_sign
    assert_raises(ArgumentError) do
      @helper.json_extract('pay_charges.object', '$.paid')
    end
  end

  def test_rejects_json_key_with_dots
    # Dots are not allowed in json_key (only in table_column)
    assert_raises(ArgumentError) do
      @helper.json_extract('pay_charges.object', 'nested.key')
    end
  end

  def test_rejects_json_key_starting_with_number
    assert_raises(ArgumentError) do
      @helper.json_extract('pay_charges.object', '123key')
    end
  end

  def test_rejects_empty_json_key
    assert_raises(ArgumentError) do
      @helper.json_extract('pay_charges.object', '')
    end
  end

  def test_rejects_nil_json_key
    assert_raises(ArgumentError) do
      @helper.json_extract('pay_charges.object', nil)
    end
  end

  def test_rejects_json_key_with_spaces
    assert_raises(ArgumentError) do
      @helper.json_extract('pay_charges.object', 'paid status')
    end
  end

  def test_rejects_json_key_with_special_characters
    assert_raises(ArgumentError) do
      @helper.json_extract('pay_charges.object', 'paid!')
    end
  end

  # ============================================================================
  # DATABASE ADAPTER OUTPUT
  # ============================================================================

  def test_generates_sqlite_syntax
    # Our test environment uses SQLite
    result = @helper.json_extract('pay_charges.object', 'paid')

    assert_equal "json_extract(pay_charges.object, '$.paid')", result
  end

  # ============================================================================
  # ERROR MESSAGE QUALITY
  # ============================================================================

  def test_error_message_includes_invalid_value_for_table_column
    error = assert_raises(ArgumentError) do
      @helper.json_extract('invalid;column', 'paid')
    end

    assert_includes error.message, 'invalid;column'
    assert_includes error.message, 'table_column'
  end

  def test_error_message_includes_invalid_value_for_json_key
    error = assert_raises(ArgumentError) do
      @helper.json_extract('pay_charges.object', 'invalid;key')
    end

    assert_includes error.message, 'invalid;key'
    assert_includes error.message, 'json_key'
  end
end
