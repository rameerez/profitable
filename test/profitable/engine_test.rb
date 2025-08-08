# frozen_string_literal: true
require "test_helper"

class EngineIntegrationTest < Minitest::Test
  include Rails.application.routes.url_helpers

  def setup
    super
    # Define routes for the engine in the test app
    TestApp.routes.draw do
      mount Profitable::Engine => "/profitable"
    end
  end

  def test_dashboard_renders
    # seed some data so view calls do not blow up
    customer = Pay::Customer.create!(processor: "stripe")
    Pay::Subscription.create!(
      customer: customer,
      processor: "stripe",
      status: "active",
      current_period_start: Time.now - 1.day,
      current_period_end: Time.now + 1.day,
      data: { "subscription_items" => [{ "price" => { "unit_amount" => 1000, "recurring" => { "interval" => "month", "interval_count" => 1 } } }] }
    )

    app = Rack::Builder.new do
      map "/profitable" do
        run Profitable::Engine
      end
    end.to_app

    env = Rack::MockRequest.env_for("/profitable")
    status, _headers, body_enum = app.call(env)
    body = String.new
    body_enum.each { |chunk| body << chunk }
    assert_equal 200, status
    assert_includes body, "total customers"
    assert_includes body, "MRR"
    assert_includes body, "Valuation at 3x ARR"
  end
end