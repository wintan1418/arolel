require "test_helper"

class SignupNudgeTest < ActionDispatch::IntegrationTest
  test "guest pages include signup nudge" do
    get root_path

    assert_response :success
    assert_select "[data-controller='signup-nudge']"
    assert_select "a[href='#{signup_path}']", text: "Create free account"
  end

  test "signed in pages do not include signup nudge" do
    sign_in_as users(:one)

    get root_path

    assert_response :success
    assert_select "[data-controller='signup-nudge']", count: 0
  end
end
