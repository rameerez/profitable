# frozen_string_literal: true

require_relative "lib/profitable/version"

Gem::Specification.new do |spec|
  spec.name = "profitable"
  spec.version = Profitable::VERSION
  spec.authors = ["rameerez"]
  spec.email = ["rubygems@rameerez.com"]

  spec.summary = "Calculate the MRR, ARR, churn, LTV, ARPU, total revenue & est. valuation of your `pay`-powered Rails SaaS"
  spec.description = "Calculate SaaS metrics like the MRR, ARR, churn, LTV, ARPU, total revenue, estimated valuation, and other business metrics of your `pay`-powered Rails app – and display them in a simple dashboard."
  spec.homepage = "https://github.com/rameerez/profitable"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rameerez/profitable"
  spec.metadata["changelog_uri"] = "https://github.com/rameerez/profitable/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "pay", ">= 7.0.0"
  spec.add_dependency "activesupport", ">= 5.2"

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
