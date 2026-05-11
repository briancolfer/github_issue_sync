# frozen_string_literal: true

# Standalone helper for spec/lib/qa_tools/**_spec.rb
# Does NOT load Rails — these specs test plain Ruby lib classes only.

require "vcr"
require "webmock/rspec"

# Add lib/ to the load path so qa_tools classes can be required directly.
$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

VCR.configure do |config|
  config.cassette_library_dir = File.expand_path("../fixtures/vcr_cassettes", __FILE__)
  config.hook_into :webmock
  config.configure_rspec_metadata! # enables :vcr tag on examples / groups

  # Allow Capybara's internal server health-check (__identify__) and any other
  # localhost traffic (e.g. from system test setup) to pass through unimpeded.
  # Without this, VCR intercepts those requests and raises UnhandledHTTPRequestError
  # when no cassette is in use.
  config.ignore_localhost = true

  # Never record real tokens in cassettes.
  config.filter_sensitive_data("<GITHUB_TOKEN>") do |interaction|
    auth = interaction.request.headers["Authorization"]&.first
    auth&.sub(/\ABearer /, "")
  end

  # Default record mode: :none in CI, :new_episodes locally so a developer
  # can re-record by deleting the cassette file.
  config.default_cassette_options = {
    record: ENV["CI"] ? :none : :new_episodes,
    match_requests_on: %i[method uri]
  }
end

# Block all real HTTP except localhost — anything not covered by a cassette
# will raise an explicit error rather than silently succeeding or timing out.
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random
end
