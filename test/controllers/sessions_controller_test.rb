require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)

    delete session_path

    assert_redirected_to root_path
    assert_empty cookies[:session_id]
  end

  test "sign in returns to the tool the user came from" do
    get new_session_path(return_to: "/invoice")
    post session_path, params: { email_address: users(:one).email_address, password: "password" }

    assert_redirected_to "/invoice"
  end

  test "sign in ignores off-site return_to values" do
    get new_session_path(return_to: "https://evil.example/phish")
    post session_path, params: { email_address: users(:one).email_address, password: "password" }

    assert_redirected_to root_url
  end

  test "signed-in header offers sign out everywhere" do
    sign_in_as(users(:one))

    get heic_path

    assert_select "header form[action='#{session_path}'] button", text: "Sign out", minimum: 1
  end
end
