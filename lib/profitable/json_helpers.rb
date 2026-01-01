# frozen_string_literal: true

module Profitable
  module JsonHelpers
    # Returns the appropriate JSON extraction syntax for the current database adapter
    # Supports PostgreSQL, MySQL (5.7.9+), and SQLite
    #
    # @param table_column [String] The table and column name (e.g., 'pay_charges.object')
    # @param json_key [String] The JSON key to extract (e.g., 'paid', 'status')
    # @return [String] Database-specific SQL for JSON extraction
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
    #   # => "json_extract(pay_charges.object, '$.paid')"
    def json_extract(table_column, json_key)
      adapter = ActiveRecord::Base.connection.adapter_name.downcase

      case adapter
      when /postgres/
        "#{table_column} ->> '#{json_key}'"
      when /mysql/, /trilogy/
        # MySQL 5.7.9+ supports JSON_EXTRACT and ->> operator
        # We use JSON_UNQUOTE(JSON_EXTRACT()) for maximum compatibility
        "JSON_UNQUOTE(JSON_EXTRACT(#{table_column}, '$.#{json_key}'))"
      when /sqlite/
        "json_extract(#{table_column}, '$.#{json_key}')"
      else
        # Fallback to PostgreSQL syntax for unknown adapters
        Rails.logger.warn("Unknown database adapter '#{adapter}' for JSON extraction. Falling back to PostgreSQL syntax.")
        "#{table_column} ->> '#{json_key}'"
      end
    end
  end
end
