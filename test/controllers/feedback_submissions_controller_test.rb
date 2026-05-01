require "test_helper"

class FeedbackSubmissionsControllerTest < ActionDispatch::IntegrationTest
  test "roadmap page shows suggestion form" do
    get roadmap_path

    assert_response :success
    assert_select "form[action='#{feedback_submissions_path}']"
    assert_select "input[name='feedback_submission[kind]'][value='suggestion']"
    assert_select "textarea[name='feedback_submission[message]']"
  end

  test "contact page shows message form" do
    get contact_path

    assert_response :success
    assert_select "form[action='#{feedback_submissions_path}']"
    assert_select "input[name='feedback_submission[kind]'][value='contact']"
    assert_select "textarea[name='feedback_submission[message]']"
  end

  test "creates roadmap suggestion with paid interest" do
    assert_difference "FeedbackSubmission.suggestions.count", 1 do
      post feedback_submissions_path, params: {
        feedback_submission: {
          kind: "suggestion",
          email: "person@example.com",
          feature_area: "pdf",
          message: "Please add OCR for scanned receipts.",
          willing_to_pay: "1",
          budget_range: "5_15"
        }
      }
    end

    submission = FeedbackSubmission.last
    assert submission.willing_to_pay?
    assert_equal "pdf", submission.feature_area
    assert_redirected_to roadmap_path
  end

  test "creates contact message" do
    assert_difference "FeedbackSubmission.contacts.count", 1 do
      post feedback_submissions_path, params: {
        feedback_submission: {
          kind: "contact",
          name: "Reader",
          email: "reader@example.com",
          subject: "Hello",
          message: "This is useful."
        }
      }
    end

    assert_redirected_to contact_path
  end
end
