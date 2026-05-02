module Admin
  class DashboardController < BaseController
    def index
      set_nav :admin
      page_title "Admin · Arolel"

      @totals = {
        users: User.count,
        super_admins: User.where(super_admin: true).count,
        visits_today: ActivityEvent.since(Time.current.beginning_of_day).count,
        visits_7d: ActivityEvent.since(7.days.ago).count,
        visits_30d: ActivityEvent.since(30.days.ago).count,
        invoices: Invoice.count,
        boards: Board.count,
        url_sets: UrlSet.count,
        signatures: DigitalSignature.count,
        conversions_7d: ToolRun.since(7.days.ago).count,
        conversion_failures_7d: ToolRun.failed.since(7.days.ago).count,
        active_media_jobs: VideoCompression.active.count,
        failed_media_jobs_24h: VideoCompression.where(status: "failed", created_at: 24.hours.ago..).count,
        feedback_7d: FeedbackSubmission.where(occurred_at: 7.days.ago..).count,
        paid_interest: FeedbackSubmission.paid_interest.count
      }

      @visits_by_day = ActivityEvent
        .since(6.days.ago.beginning_of_day)
        .group("DATE(occurred_at)")
        .order(Arel.sql("DATE(occurred_at) ASC"))
        .count

      @top_tools = ActivityEvent
        .since(30.days.ago)
        .group(Arel.sql("split_part(path, '/', 2)"))
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(8)
        .count

      @conversion_stats = ToolRun
        .since(30.days.ago)
        .group(:operation, :status)
        .count

      @top_paths = ActivityEvent
        .since(30.days.ago)
        .group(:path)
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(10)
        .count

      @recent_events = ActivityEvent.includes(:user).recent.limit(30)
      @recent_tool_runs = ToolRun.includes(:user).recent.limit(20)
      @recent_feedback = FeedbackSubmission.includes(:user).recent.limit(12)
      @recent_users = User.order(created_at: :desc).limit(10)
      @recent_media_jobs = VideoCompression.includes(:user).recent.limit(15)
      @mail_audience_counts = {
        all_users: User.count,
        active_30d: User.joins(:activity_events).merge(ActivityEvent.since(30.days.ago)).distinct.count,
        recent_signups_30d: User.where(created_at: 30.days.ago..).count
      }
      @user_rows = User
        .left_joins(:activity_events)
        .select("users.*, MAX(activity_events.occurred_at) AS last_seen_at, COUNT(activity_events.id) AS activity_count")
        .group("users.id")
        .order(Arel.sql("MAX(activity_events.occurred_at) DESC NULLS LAST, users.created_at DESC"))
        .limit(20)
    end
  end
end
