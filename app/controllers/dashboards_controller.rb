class DashboardsController < ApplicationController
  before_action { set_nav :dashboard }

  def show
    page_title "Dashboard · Arolel"
    @invoices = current_user.invoices.recent.limit(50)
    @boards   = current_user.boards.order(created_at: :desc).limit(50)
    @url_sets = current_user.url_sets.order(created_at: :desc).limit(50)
    @digital_signatures = current_user.digital_signatures.recent.limit(50)
    @tool_runs = current_user.tool_runs.recent.limit(12)
  end
end
