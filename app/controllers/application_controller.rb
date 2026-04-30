class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  after_action :record_activity_event

  helper_method :current_nav, :page_title, :meta_description, :current_user, :signed_in?

  private

  def set_nav(key)
    @current_nav = key
  end

  def current_nav
    @current_nav ||= :home
  end

  def page_title(title = nil)
    @page_title = title if title
    @page_title
  end

  def meta_description(desc = nil)
    @meta_description = desc if desc
    @meta_description
  end

  def current_user
    authenticated?
    Current.user
  end

  def signed_in?
    authenticated?
  end

  def record_activity_event
    ActivityEvent.record_request(request: request, response: response, user: current_user)
  end
end
