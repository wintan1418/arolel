require "test_helper"

class SignupNudgeTest < ActionDispatch::IntegrationTest
  test "guest pages include signup nudge" do
    get root_path

    assert_response :success
    assert_select "[data-controller='signup-nudge']"
    assert_select "a[href='#{signup_path(return_to: '/')}']", text: "Sign up free"
  end

  test "auth pages do not include signup nudge" do
    get new_session_path

    assert_response :success
    assert_select "[data-controller='signup-nudge']", count: 0
  end

  test "signed in pages do not include signup nudge" do
    sign_in_as users(:one)

    get root_path

    assert_response :success
    assert_select "[data-controller='signup-nudge']", count: 0
  end
end
