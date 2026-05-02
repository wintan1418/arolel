class AdminMailer < ApplicationMailer
  def test_message(to:, subject:, body:)
    @body = body
    mail(to: to, subject: subject)
  end

  def user_update_message(to:, bcc:, reply_to:, subject:, body:)
    @body = body
    mail(to: to, bcc: bcc, reply_to: reply_to, subject: subject)
  end
end
