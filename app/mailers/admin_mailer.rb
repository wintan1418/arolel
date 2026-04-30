class AdminMailer < ApplicationMailer
  def test_message(to:, subject:, body:)
    @body = body
    mail(to: to, subject: subject)
  end
end
