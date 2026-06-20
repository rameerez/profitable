# frozen_string_literal: true

# SimpleCov configuration file (auto-loaded before test suite)
# This keeps test_helper.rb clean and follows best practices

SimpleCov.start do
  # Use SimpleFormatter for terminal-only output (no HTML generation)
  formatter SimpleCov::Formatter::SimpleFormatter

  # Track coverage for the lib directory (gem source code)
  add_filter "/test/"

  # Exclude Rails engine components that require integration testing
  # These are tested via Appraisal with a full Rails app
  add_filter "/lib/profitable/engine.rb"
  add_filter "/app/"

  # Exclude the main profitable.rb entry point - it only requires the engine
  # and the gem's components. The test harness loads those components directly
  # (test_helper.rb) because requiring the engine needs a full Rails app, so
  # all core logic in lib/profitable/*.rb runs as real production code paths.
  add_filter "/lib/profitable.rb"

  # Track the lib directory (core gem logic)
  track_files "lib/**/*.rb"

  # Enable branch coverage for more detailed metrics
  enable_coverage :branch

  # Set minimum coverage threshold for the core calculation logic
  # The Rails engine/controllers are tested separately via Appraisal
  minimum_coverage line: 80, branch: 70

  # Disambiguate parallel test runs
  command_name "Job #{ENV['TEST_ENV_NUMBER']}" if ENV['TEST_ENV_NUMBER']
end

# Print coverage summary to terminal after tests complete
SimpleCov.at_exit do
  SimpleCov.result.format!
  puts "\n" + "=" * 60
  puts "COVERAGE SUMMARY"
  puts "=" * 60
  puts "Line Coverage:   #{SimpleCov.result.covered_percent.round(2)}%"
  puts "Branch Coverage: #{SimpleCov.result.coverage_statistics[:branch]&.percent&.round(2) || 'N/A'}%"
  puts "=" * 60
end
