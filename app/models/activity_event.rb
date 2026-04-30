require "openssl"

class ActivityEvent < ApplicationRecord
  belongs_to :user, optional: true

  USER_AGENT_LIMIT = 240
  REFERRER_LIMIT = 500

  scope :recent, -> { order(occurred_at: :desc) }
  scope :since, ->(time) { where(occurred_at: time..) }

  def self.record_request(request:, response:, user:)
    return unless trackable_request?(request)

    create!(
      user: user,
      event_name: request.get? ? "page_view" : "request",
      controller_action: "#{request.params[:controller]}##{request.params[:action]}",
      request_method: request.request_method,
      path: request.fullpath.to_s.first(500),
      status: response.status,
      ip_hash: hash_ip(request.remote_ip),
      user_agent: request.user_agent.to_s.first(USER_AGENT_LIMIT),
      referrer: request.referrer.to_s.first(REFERRER_LIMIT),
      occurred_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.warn("[activity] skipped: #{e.class}: #{e.message}")
  end

  def self.trackable_request?(request)
    return false unless request.format.html? || request.format.json?
    return false if request.path.start_with?("/assets", "/rails/active_storage", "/admin", "/up")
    return false if request.path.in?([ "/favicon.ico", "/service-worker", "/manifest", "/media-debug" ])

    true
  end

  def self.hash_ip(ip)
    return if ip.blank?

    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, ip)
  end
end
