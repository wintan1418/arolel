require "test_helper"

class ActivityEventTest < ActiveSupport::TestCase
  FakeFormat = Data.define(:html_value, :json_value) do
    def html? = html_value
    def json? = json_value
  end

  FakeRequest = Data.define(
    :request_method,
    :format,
    :path,
    :params,
    :fullpath,
    :remote_ip,
    :user_agent,
    :referrer
  )

  FakeResponse = Data.define(:status)

  test "records get and head requests as page views" do
    %w[GET HEAD].each do |method|
      ActivityEvent.record_request(request: fake_request(method), response: fake_response, user: nil)

      assert_equal "page_view", ActivityEvent.order(:created_at).last.event_name
    end
  end

  test "records non-navigation requests as requests" do
    ActivityEvent.record_request(request: fake_request("POST"), response: fake_response, user: nil)

    assert_equal "request", ActivityEvent.last.event_name
  end

  private

  def fake_request(method)
    FakeRequest.new(
      request_method: method,
      format: FakeFormat.new(true, false),
      path: "/",
      params: { controller: "pages", action: "home" },
      fullpath: "/",
      remote_ip: "127.0.0.1",
      user_agent: "Rails test",
      referrer: nil
    )
  end

  def fake_response
    FakeResponse.new(200)
  end
end
