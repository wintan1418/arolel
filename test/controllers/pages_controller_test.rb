require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home page includes contract maker in the tool catalog" do
    get root_path

    assert_response :success
    assert_select "[data-controller='mobile-nav']"
    assert_select "[data-mobile-nav-target='toggle'][aria-controls='mobile-nav-panel']"
    # The panel ships closed so the menu never flashes open before JavaScript runs.
    assert_select "#mobile-nav-panel[hidden]"
    assert_select "#mobile-nav-panel a[href='#{new_session_path(return_to: '/')}']", text: "Sign in"
    assert_includes response.body, "Ten everyday tools"
    assert_select "a[href='#{new_contract_path}']", text: /Contract maker/
    assert_includes response.body, "/contract"
    assert_includes response.body, "temporary upload · protected queue"
  end

  test "media pages use protected queue UI" do
    %w[mp4-to-mp3 webm-to-mp4 compress-video].each do |op|
      get media_path(op: op)

      assert_response :success
      assert_select "a[href='#{new_session_path(return_to: media_path(op: op))}']", text: "Sign in"
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
