require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "media pages use protected queue UI" do
    %w[mp4-to-mp3 webm-to-mp4 compress-video].each do |op|
      get media_path(op: op)

      assert_response :success
      assert_select "a[href='#{new_session_path}']", text: "Log in"
      assert_includes response.body, "Protected queue"
      assert_includes response.body, "Server protection"
      assert_includes response.body, "Free for now while capacity is being tested"
    end
  end

  test "sign page shows uploaded signature preview placeholder" do
    get sign_path

    assert_response :success
    assert_select "[data-sign-target='uploadPanel']"
    assert_select "[data-sign-target='signaturePreview']"
    assert_includes response.body, "This does not upload to the server"
  end
end
