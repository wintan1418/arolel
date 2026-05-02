require "test_helper"

class Admin::UserMessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    ActionMailer::Base.deliveries.clear
  end

  test "super admin can send user update to all users" do
    user = users(:one)
    user.update!(super_admin: true)
    sign_in_as user

    post admin_user_messages_path, params: {
      audience: "all_users",
      subject: "Platform update",
      body: "Arolel media tools are being improved."
    }

    assert_redirected_to admin_root_path
    assert_equal 1, ActionMailer::Base.deliveries.size

    message = ActionMailer::Base.deliveries.last
    assert_equal [ user.email_address ], message.to
    assert_equal [ users(:one).email_address, users(:two).email_address ].sort, message.bcc.sort
    assert_equal "Platform update", message.subject
  end

  test "manual audience only sends to existing users" do
    user = users(:one)
    user.update!(super_admin: true)
    sign_in_as user

    post admin_user_messages_path, params: {
      audience: "manual",
      emails: "two@example.com\nmissing@example.com",
      subject: "Direct note",
      body: "Testing manual send."
    }

    assert_redirected_to admin_root_path
    assert_equal [ users(:two).email_address ], ActionMailer::Base.deliveries.last.bcc
  end

  test "non admin cannot send user update" do
    sign_in_as users(:two)

    post admin_user_messages_path, params: {
      audience: "all_users",
      subject: "Nope",
      body: "Should not send."
    }

    assert_redirected_to dashboard_path
    assert_empty ActionMailer::Base.deliveries
  end
end
