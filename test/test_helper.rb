ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/match_rating_test_data"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    include MatchRatingTestData

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.

    # Add more helper methods to be used by all tests here...
  end
end
