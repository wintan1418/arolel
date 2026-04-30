class ApplicationMailer < ActionMailer::Base
  default from: -> { "Arolel <no-reply@#{ENV.fetch("MAIL_DOMAIN", ENV.fetch("PUBLIC_HOST", ENV.fetch("APP_HOST", "arolel.com")).split(",").first.strip)}>" }
  layout "mailer"
end
