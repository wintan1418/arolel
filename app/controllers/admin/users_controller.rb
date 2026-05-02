module Admin
  class UsersController < BaseController
    USER_LIMIT = 50

    def index
      set_nav :admin
      page_title "Admin users · Arolel"

      @filters = {
        q: params[:q].to_s.strip,
        role: params[:role].presence_in(%w[all admin user]) || "all",
        activity: params[:activity].presence_in(%w[all active_30d inactive_30d never]) || "all",
        joined: params[:joined].presence_in(%w[all last_7d last_30d]) || "all"
      }

      @totals = {
        users: User.count,
        admins: User.where(super_admin: true).count,
        active_30d: User.joins(:activity_events).merge(ActivityEvent.since(30.days.ago)).distinct.count,
        recent_signups_30d: User.where(created_at: 30.days.ago..).count
      }

      @users = filtered_users.limit(USER_LIMIT)
    end

    private

    def filtered_users
      scope = User
        .left_joins(:activity_events)
        .select("users.*, MAX(activity_events.occurred_at) AS last_seen_at, COUNT(activity_events.id) AS activity_count")
        .group("users.id")

      if @filters[:q].present?
        scope = scope.where("users.email_address ILIKE ?", "%#{User.sanitize_sql_like(@filters[:q])}%")
      end

      scope = case @filters[:role]
      when "admin"
        scope.where(super_admin: true)
      when "user"
        scope.where(super_admin: false)
      else
        scope
      end

      scope = case @filters[:joined]
      when "last_7d"
        scope.where(users: { created_at: 7.days.ago.. })
      when "last_30d"
        scope.where(users: { created_at: 30.days.ago.. })
      else
        scope
      end

      scope = case @filters[:activity]
      when "active_30d"
        scope.having("MAX(activity_events.occurred_at) >= ?", 30.days.ago)
      when "inactive_30d"
        scope.having("MAX(activity_events.occurred_at) < ? OR MAX(activity_events.occurred_at) IS NULL", 30.days.ago)
      when "never"
        scope.having("COUNT(activity_events.id) = 0")
      else
        scope
      end

      scope.order(Arel.sql("MAX(activity_events.occurred_at) DESC NULLS LAST, users.created_at DESC"))
    end
  end
end
