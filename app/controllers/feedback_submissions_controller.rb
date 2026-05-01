class FeedbackSubmissionsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 10.minutes, only: :create,
             with: -> { redirect_back fallback_location: roadmap_path, alert: "Too many messages. Please try again soon." }

  def create
    submission = FeedbackSubmission.new(feedback_submission_params)
    submission.user = current_user
    submission.email = current_user.email_address if submission.email.blank? && current_user
    submission.ip_hash = ActivityEvent.hash_ip(request.remote_ip)
    submission.user_agent = request.user_agent.to_s.first(240)
    submission.occurred_at = Time.current

    if submission.save
      redirect_to redirect_path_for(submission), notice: thank_you_message_for(submission), status: :see_other
    else
      redirect_to redirect_path_for(submission),
                  alert: submission.errors.full_messages.to_sentence,
                  status: :see_other
    end
  end

  private

  def feedback_submission_params
    params.require(:feedback_submission).permit(
      :kind,
      :name,
      :email,
      :subject,
      :feature_area,
      :message,
      :willing_to_pay,
      :budget_range
    )
  end

  def redirect_path_for(submission)
    submission.kind == "contact" ? contact_path : roadmap_path
  end

  def thank_you_message_for(submission)
    submission.kind == "contact" ? "Thanks. Your message has been received." : "Thanks. Your roadmap suggestion has been saved."
  end
end
