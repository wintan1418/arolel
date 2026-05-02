module Admin
  class FeedbackSubmissionsController < BaseController
    FEEDBACK_LIMIT = 80

    def index
      set_nav :admin
      page_title "Admin feedback · Arolel"

      @filters = {
        q: params[:q].to_s.strip,
        kind: params[:kind].presence_in(%w[all suggestion contact]) || "all",
        status: params[:status].presence_in(%w[all new reviewed planned shipped declined]) || "all",
        paid: params[:paid].presence_in(%w[all paid unpaid]) || "all"
      }

      @totals = {
        total: FeedbackSubmission.count,
        suggestions: FeedbackSubmission.suggestions.count,
        contacts: FeedbackSubmission.contacts.count,
        paid: FeedbackSubmission.paid_interest.count,
        new_items: FeedbackSubmission.where(status: "new").count
      }

      @feedback_submissions = filtered_feedback.limit(FEEDBACK_LIMIT)
    end

    def update
      submission = FeedbackSubmission.find(params[:id])

      if submission.update(feedback_submission_params)
        redirect_back fallback_location: admin_feedback_submissions_path, notice: "Feedback status updated."
      else
        redirect_back fallback_location: admin_feedback_submissions_path,
                      alert: submission.errors.full_messages.to_sentence
      end
    end

    private

    def filtered_feedback
      scope = FeedbackSubmission.includes(:user).recent

      if @filters[:q].present?
        query = "%#{FeedbackSubmission.sanitize_sql_like(@filters[:q])}%"
        scope = scope.where(
          "feedback_submissions.email ILIKE :q OR feedback_submissions.name ILIKE :q OR feedback_submissions.subject ILIKE :q OR feedback_submissions.feature_area ILIKE :q OR feedback_submissions.message ILIKE :q",
          q: query
        )
      end

      scope = scope.where(kind: @filters[:kind]) unless @filters[:kind] == "all"
      scope = scope.where(status: @filters[:status]) unless @filters[:status] == "all"

      scope = case @filters[:paid]
      when "paid"
        scope.where(willing_to_pay: true)
      when "unpaid"
        scope.where(willing_to_pay: false)
      else
        scope
      end

      scope
    end

    def feedback_submission_params
      params.require(:feedback_submission).permit(:status)
    end
  end
end
