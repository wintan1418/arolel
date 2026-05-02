require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "media compression page is available" do
    get media_path(op: "compress-video")

    assert_response :success
    assert_select "[data-media-op-value='compress-video']"
    assert_select "input[accept*='video/mp4']"
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
