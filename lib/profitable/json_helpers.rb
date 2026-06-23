# frozen_string_literal: true

module Profitable
  module JsonHelpers
    # Regex patterns for validating SQL identifiers to prevent SQL injection
    # Only allows: alphanumeric characters, underscores, and dots (for table.column format)
    VALID_TABLE_COLUMN_PATTERN = /\A[a-zA-Z_][a-zA-Z0-9_.]*\z/
    VALID_JSON_KEY_PATTERN = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

    # Returns the appropriate JSON extraction syntax for the current database adapter,
    # always yielding a TEXT-typed value so comparisons behave identically everywhere.
    # Supports PostgreSQL, MySQL (5.7.9+), and SQLite.
    #
    # @param table_column [String] The table and column name (e.g., 'pay_charges.object')
    # @param json_key [String] The JSON key to extract (e.g., 'paid', 'status')
    # @return [String] Database-specific SQL for JSON extraction
    # @raise [ArgumentError] if table_column or json_key contain invalid characters
    #
    # @example PostgreSQL
    #   json_extract('pay_charges.object', 'paid')
    #   # => "pay_charges.object ->> 'paid'"
    #
    # @example MySQL
    #   json_extract('pay_charges.object', 'paid')
    #   # => "JSON_UNQUOTE(JSON_EXTRACT(pay_charges.object, '$.paid'))"
    #
    # @example SQLite
    #   json_extract('pay_charges.object', 'paid')
    #   # => "CAST(json_extract(pay_charges.object, '$.paid') AS TEXT)"
    def json_extract(table_column, json_key)
      # Validate inputs to prevent SQL injection
      validate_table_column!(table_column)
      validate_json_key!(json_key)

      adapter = ActiveRecord::Base.connection.adapter_name.downcase

      case adapter
      when /postgres/
        "#{table_column} ->> '#{json_key}'"
      when /mysql/, /trilogy/
        # MySQL 5.7.9+ supports JSON_EXTRACT and ->> operator
        # We use JSON_UNQUOTE(JSON_EXTRACT()) for maximum compatibility
        "JSON_UNQUOTE(JSON_EXTRACT(#{table_column}, '$.#{json_key}'))"
      when /sqlite/
        # SQLite returns JSON booleans as integers (0/1), unlike ->> on
        # PostgreSQL/MySQL which return text. CAST keeps the adapters in sync.
        "CAST(json_extract(#{table_column}, '$.#{json_key}') AS TEXT)"
      else
        # Fallback to PostgreSQL syntax for unknown adapters
        Rails.logger.warn("Unknown database adapter '#{adapter}' for JSON extraction. Falling back to PostgreSQL syntax.")
        "#{table_column} ->> '#{json_key}'"
      end
    end

    private

    def validate_table_column!(table_column)
      unless table_column.is_a?(String) && table_column.match?(VALID_TABLE_COLUMN_PATTERN)
        raise ArgumentError, "Invalid table_column format: #{table_column.inspect}. " \
          "Must be alphanumeric with underscores/dots only (e.g., 'pay_charges.object')."
      end
    end

    def validate_json_key!(json_key)
      unless json_key.is_a?(String) && json_key.match?(VALID_JSON_KEY_PATTERN)
        raise ArgumentError, "Invalid json_key format: #{json_key.inspect}. " \
          "Must be alphanumeric with underscores only (e.g., 'paid', 'status')."
      end
    end
  end
end
