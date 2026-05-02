require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  test "super admin can view user directory" do
    user = users(:one)
    user.update!(super_admin: true)
    sign_in_as user

    get admin_users_path

    assert_response :success
    assert_includes response.body, "User directory"
    assert_includes response.body, users(:one).email_address
    assert_includes response.body, users(:two).email_address
  end

  test "directory filters by query and role" do
    admin = users(:one)
    admin.update!(super_admin: true)
    sign_in_as admin

    get admin_users_path, params: { q: "two@", role: "user" }

    assert_response :success
    assert_includes response.body, users(:two).email_address
    assert_not_includes response.body, "User ##{users(:one).id}"
    assert_includes response.body, "Results 1"
  end

  test "directory filters by recent activity" do
    admin = users(:one)
    admin.update!(super_admin: true)
    sign_in_as admin

    ActivityEvent.create!(
      user: users(:two),
      event_name: "page_view",
      controller_action: "pages#home",
      request_method: "GET",
      path: "/",
      status: 200,
      occurred_at: 1.day.ago
    )

    get admin_users_path, params: { activity: "active_30d" }

    assert_response :success
    assert_includes response.body, users(:two).email_address
    assert_not_includes response.body, "User ##{users(:one).id}"
    assert_includes response.body, "Results 1"
  end

  test "non admin is redirected away from user directory" do
    sign_in_as users(:two)

    get admin_users_path

    assert_redirected_to dashboard_path
  end
end
