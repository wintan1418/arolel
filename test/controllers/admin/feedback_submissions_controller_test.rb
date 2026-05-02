require "test_helper"

class Admin::FeedbackSubmissionsControllerTest < ActionDispatch::IntegrationTest
  test "super admin can view feedback inbox" do
    admin = users(:one)
    admin.update!(super_admin: true)
    sign_in_as admin

    FeedbackSubmission.create!(
      kind: "suggestion",
      status: "new",
      name: "Arolel user",
      email: "person@example.com",
      feature_area: "pdf",
      message: "Please add OCR for scanned files.",
      willing_to_pay: true,
      occurred_at: Time.current
    )

    get admin_feedback_submissions_path

    assert_response :success
    assert_includes response.body, "Feedback inbox"
    assert_includes response.body, "Please add OCR for scanned files."
    assert_includes response.body, "person@example.com"
  end

  test "super admin can update feedback status" do
    admin = users(:one)
    admin.update!(super_admin: true)
    sign_in_as admin

    submission = FeedbackSubmission.create!(
      kind: "contact",
      status: "new",
      name: "Someone",
      message: "Need enterprise pricing.",
      occurred_at: Time.current
    )

    patch admin_feedback_submission_path(submission), params: {
      feedback_submission: { status: "reviewed" }
    }

    assert_redirected_to admin_feedback_submissions_path
    assert_equal "reviewed", submission.reload.status
  end

  test "non admin is redirected away from feedback inbox" do
    sign_in_as users(:two)

    get admin_feedback_submissions_path

    assert_redirected_to dashboard_path
  end
end
