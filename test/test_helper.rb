ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/payments_test_helper"
require_relative "test_helpers/voyage_test_helper"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all
    include VoyageTestHelper

    # every test talks to a scripted model, never to the network
    setup { Llm.client = @llm = Llm::Fake.new }
    teardown { Llm.client = nil }
  end
end
