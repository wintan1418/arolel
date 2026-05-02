require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "media compression page is available" do
    get media_path(op: "compress-video")

    assert_response :success
    assert_select "[data-media-op-value='compress-video']", false
    assert_select "a[href='#{new_session_path}']", text: "Log in"
    assert_includes response.body, "Protected queue"
    assert_includes response.body, "Compress video"
  end

  test "sign page shows uploaded signature preview placeholder" do
    get sign_path

    assert_response :success
    assert_select "[data-sign-target='uploadPanel']"
    assert_select "[data-sign-target='signaturePreview']"
    assert_includes response.body, "This does not upload to the server"
  end
end
