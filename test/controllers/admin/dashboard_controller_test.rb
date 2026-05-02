require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "super admin can view admin dashboard" do
    user = users(:one)
    user.update!(super_admin: true)
    sign_in_as user

    get admin_root_path

    assert_response :success
    assert_includes response.body, "Arolel control room"
    assert_includes response.body, "Send user update"
  end

  test "non admin is redirected away from admin dashboard" do
    sign_in_as users(:two)

    get admin_root_path

    assert_redirected_to dashboard_path
  end
end
