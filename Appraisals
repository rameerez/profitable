# frozen_string_literal: true

# Test minimum supported Rails version (with latest Pay)
appraise "rails-7.2" do
  gem "rails", "~> 7.2.0"
  gem "pay", "~> 11.0"
  gem "stripe", "~> 18.0"
end

# Test latest Rails version (with latest Pay)
appraise "rails-8.1" do
  gem "rails", "~> 8.1.0"
  gem "pay", "~> 11.0"
  gem "stripe", "~> 18.0"
end

# Test against Pay 7.x (original minimum supported version)
appraise "pay-7.3" do
  gem "pay", "~> 7.3.0"
  gem "stripe", "~> 12.0"
  gem "rails", "~> 8.1.0"
end

# Test against Pay 8.x
appraise "pay-8.3" do
  gem "pay", "~> 8.3.0"
  gem "stripe", "~> 13.0"
  gem "rails", "~> 8.1.0"
end

# Test against Pay 9.x
appraise "pay-9.0" do
  gem "pay", "~> 9.0.0"
  gem "stripe", "~> 13.0"
  gem "rails", "~> 8.1.0"
end

# Test against Pay 10.x (newly supported version with object column)
appraise "pay-10.0" do
  gem "pay", "~> 10.0.0"
  gem "stripe", "~> 15.0"
  gem "rails", "~> 8.1.0"
end

# Test against Pay 11.x (latest version as of 2025)
appraise "pay-11.0" do
  gem "pay", "~> 11.0"
  gem "stripe", "~> 18.0"
  gem "rails", "~> 8.1.0"
end
