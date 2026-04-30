module Admin
  class EmailTestsController < BaseController
    def create
      AdminMailer.test_message(
        to: params[:to].presence || current_user.email_address,
        subject: params[:subject].presence || "Arolel email test",
        body: params[:body].presence || "This confirms Arolel can send email through SMTP."
      ).deliver_now

      redirect_to admin_root_path, notice: "Test email sent."
    rescue StandardError => e
      redirect_to admin_root_path, alert: "Email failed: #{e.message}"
    end
  end
end
