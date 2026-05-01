class DocumentConversionsController < ApplicationController
  allow_unauthenticated_access
  before_action :rate_limit_conversions, only: :create

  def create
    result = DocumentConverter.new(operation: params[:op], upload: params[:file]).call
    record_tool_run(status: "succeeded", result: result)

    send_data result.bytes,
              filename: result.filename,
              type: result.content_type,
              disposition: "attachment"
  rescue DocumentConverter::Error => e
    record_tool_run(status: "failed", error: e)
    redirect_to pdf_path(op: params[:op]), alert: e.message, status: :see_other
  end

  private

  def rate_limit_conversions
    window = Time.current.to_i / 1.hour
    key = "document-conversions:#{request.remote_ip}:#{window}"
    count = Rails.cache.increment(key, 1, expires_in: 1.hour)
    count ||= Rails.cache.write(key, 1, expires_in: 1.hour) && 1

    return if count <= 20

    redirect_to pdf_path(op: params[:op]),
                alert: "Too many conversions from this network. Please try again in about an hour.",
                status: :see_other
  end

  def record_tool_run(status:, result: nil, error: nil)
    upload = params[:file]

    ToolRun.create!(
      user: current_user,
      tool_key: "document_conversion",
      operation: params[:op],
      status: status,
      input_filename: upload&.original_filename,
      input_bytes: upload&.size,
      output_filename: result&.filename,
      output_bytes: result&.bytes&.bytesize,
      error_message: error&.message&.first(255),
      metadata: { content_type: upload&.content_type }.compact,
      occurred_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.warn("[tool_run] skipped: #{e.class}: #{e.message}")
  end
end
