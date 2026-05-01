class DocumentConversionsController < ApplicationController
  allow_unauthenticated_access

  def create
    result = DocumentConverter.new(operation: params[:op], upload: params[:file]).call

    send_data result.bytes,
              filename: result.filename,
              type: result.content_type,
              disposition: "attachment"
  rescue DocumentConverter::Error => e
    redirect_to pdf_path(op: params[:op]), alert: e.message
  end
end
