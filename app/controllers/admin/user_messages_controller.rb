module Admin
  class UserMessagesController < BaseController
    MAX_RECIPIENTS = ENV.fetch("ADMIN_BROADCAST_MAX_RECIPIENTS", 150).to_i

    def create
      recipients = recipients_for(params[:audience], params[:emails])
      raise ArgumentError, "Choose at least one user to email." if recipients.empty?
      raise ArgumentError, "This server is capped at #{MAX_RECIPIENTS} recipients per send right now." if recipients.size > MAX_RECIPIENTS

      subject = params[:subject].to_s.strip
      body = params[:body].to_s.strip
      raise ArgumentError, "Subject cannot be blank." if subject.blank?
      raise ArgumentError, "Message cannot be blank." if body.blank?

      AdminMailer.user_update_message(
        to: current_user.email_address,
        bcc: recipients,
        reply_to: current_user.email_address,
        subject: subject,
        body: body
      ).deliver_now

      redirect_to admin_root_path, notice: "Sent to #{recipients.size} user#{'s' unless recipients.size == 1}."
    rescue StandardError => e
      redirect_to admin_root_path, alert: "User email failed: #{e.message}"
    end

    private

    def recipients_for(audience, manual_emails)
      case audience.to_s
      when "all_users"
        User.order(:email_address).limit(MAX_RECIPIENTS + 1).pluck(:email_address)
      when "active_30d"
        User.joins(:activity_events).merge(ActivityEvent.since(30.days.ago)).distinct.order(:email_address).limit(MAX_RECIPIENTS + 1).pluck(:email_address)
      when "recent_signups_30d"
        User.where(created_at: 30.days.ago..).order(:email_address).limit(MAX_RECIPIENTS + 1).pluck(:email_address)
      when "manual"
        emails = manual_emails.to_s.split(/[\n,]/).map { |email| email.strip.downcase }.reject(&:blank?).uniq
        User.where(email_address: emails).order(:email_address).limit(MAX_RECIPIENTS + 1).pluck(:email_address)
      else
        raise ArgumentError, "Choose a valid audience."
      end
    end
  end
end
