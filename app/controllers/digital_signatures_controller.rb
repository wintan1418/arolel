class DigitalSignaturesController < ApplicationController
  allow_unauthenticated_access only: :create
  before_action :require_auth

  def create
    signature = current_user.digital_signatures.new(digital_signature_params)
    signature.name = signature.name.presence || signature.source_text.presence || "Signature"

    if signature.save
      render json: signature_payload(signature), status: :created
    else
      render json: { errors: signature.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    current_user.digital_signatures.find(params[:id]).destroy
    redirect_to dashboard_path, notice: "Signature deleted."
  end

  private

  def digital_signature_params
    params.require(:digital_signature).permit(:name, :source_text, :style_key, :image_data)
  end

  def signature_payload(signature)
    {
      id: signature.id,
      name: signature.name,
      source_text: signature.source_text,
      style_key: signature.style_key,
      image_data: signature.image_data
    }
  end

  def require_auth
    return if authenticated?

    respond_to do |format|
      format.json do
        render json: {
          error: "sign_in_required",
          login_url: new_session_path,
          register_url: new_registration_path
        }, status: :unauthorized
      end
      format.html { redirect_to new_session_path, alert: "Sign in to save signatures." }
    end
  end
end
