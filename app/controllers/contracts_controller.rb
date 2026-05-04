class ContractsController < ApplicationController
  allow_unauthenticated_access only: [ :new, :create, :update, :destroy, :edit, :draft ]
  before_action :require_auth_for_save, only: [ :create, :update, :destroy, :edit ]
  before_action :require_auth_for_ai, only: :draft
  before_action :set_contract_ai_enabled, only: [ :new, :edit ]
  before_action { set_nav :contract }
  rate_limit to: 8, within: 1.hour, only: :draft,
             with: -> { render json: { error: "rate_limited", message: "Too many AI draft requests. Try again later." }, status: :too_many_requests }

  def new
    page_title "Contract maker — draft agreements with signatures · Arolel"
    meta_description "Draft service agreements, NDAs, and consulting contracts in your browser. Reuse your saved signature, export a PDF, and save drafts to your account."
    @contract = load_contract
    @digital_signatures = signed_in? ? current_user.digital_signatures.recent.limit(12) : DigitalSignature.none
  end

  def create
    contract = current_user.contracts.new(contract_params)
    if contract.save
      respond_to do |format|
        format.html { redirect_to dashboard_path, notice: "Contract saved." }
        format.json { render json: { slug: contract.slug, title: contract.title, url: edit_contract_url(slug: contract.slug) } }
      end
    else
      respond_to do |format|
        format.html { redirect_to new_contract_path, alert: contract.errors.full_messages.to_sentence }
        format.json { render json: { errors: contract.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def edit
    @contract = current_user.contracts.find_by!(slug: params[:slug])
    @digital_signatures = current_user.digital_signatures.recent.limit(12)
    page_title "#{@contract.title} · Arolel"
    render :new
  end

  def update
    @contract = current_user.contracts.find_by!(slug: params[:slug])
    if @contract.update(contract_params)
      respond_to do |format|
        format.html { redirect_to dashboard_path, notice: "Contract updated." }
        format.json { render json: { slug: @contract.slug } }
      end
    else
      respond_to do |format|
        format.html { redirect_to edit_contract_path(slug: @contract.slug), alert: @contract.errors.full_messages.to_sentence }
        format.json { render json: { errors: @contract.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    contract = current_user.contracts.find_by!(slug: params[:slug])
    contract.destroy
    redirect_to dashboard_path, notice: "Contract deleted."
  end

  def draft
    result = ContractAiDrafter.new(
      template: params[:template],
      current_draft: draft_payload,
      messages: params[:messages],
      user: current_user
    ).call

    render json: result
  rescue ContractAiDrafter::NotConfigured => e
    render json: { error: "not_configured", message: e.message }, status: :service_unavailable
  rescue ContractAiDrafter::DraftFailed => e
    render json: { error: "draft_failed", message: e.message }, status: :unprocessable_entity
  end

  private

  def contract_params
    params.require(:contract).permit(
      :title, :template, :effective_on,
      :party_a_name, :party_a_address, :party_a_email,
      :party_b_name, :party_b_address, :party_b_email,
      :summary, :notes,
      :signer_name, :signer_image_data,
      sections: [ :heading, :body ]
    )
  end

  def require_auth_for_save
    return if signed_in?

    if request.format.json?
      render json: { error: "sign_in_required", login_url: new_session_path }, status: :unauthorized
    else
      redirect_to new_session_path, alert: "Sign in to save contracts."
    end
  end

  def load_contract
    return current_user.contracts.find_by(slug: params[:slug]) if params[:slug] && signed_in?

    Contract.new(
      template: "service",
      sections: [],
      title: Contract.suggest_title(current_user)
    )
  end

  def draft_payload
    params.require(:draft).permit(
      :title, :effective_on,
      :party_a_name, :party_a_address, :party_a_email,
      :party_b_name, :party_b_address, :party_b_email,
      :summary, :notes,
      sections: [ :heading, :body ]
    )
  end

  def require_auth_for_ai
    return if authenticated?

    render json: {
      error: "sign_in_required",
      login_url: new_session_path
    }, status: :unauthorized
  end

  def set_contract_ai_enabled
    @contract_ai_enabled = ENV["OPENAI_API_KEY"].present?
  end
end
