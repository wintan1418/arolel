module Admin
  class DashboardController < BaseController
    def index
      set_nav :admin
      page_title "Admin · Arolel"

      @totals = {
        users: User.count,
        visits_today: ActivityEvent.since(Time.current.beginning_of_day).count,
        visits_7d: ActivityEvent.since(7.days.ago).count,
        visits_30d: ActivityEvent.since(30.days.ago).count,
        invoices: Invoice.count,
        boards: Board.count,
        url_sets: UrlSet.count,
        signatures: DigitalSignature.count
      }

      @top_paths = ActivityEvent
        .since(30.days.ago)
        .group(:path)
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(10)
        .count

      @recent_events = ActivityEvent.includes(:user).recent.limit(30)
      @recent_users = User.order(created_at: :desc).limit(10)
    end
  end
end
