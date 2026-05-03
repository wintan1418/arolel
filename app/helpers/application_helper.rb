module ApplicationHelper
  def app_name
    "Arolel"
  end

  def app_host
    ENV.fetch("PUBLIC_HOST", ENV.fetch("APP_HOST", "arolel.com")).split(",").first.strip
  end

  def app_url
    ENV.fetch("PUBLIC_URL", "https://#{app_host}")
  end

  def page_javascript_entrypoint
    case current_nav
    when :heic then "heic_tool"
    when :images then "image_tool"
    when :pdf then @server_side_file_tool ? "document_conversion_tool" : "pdf_tool"
    when :invoice then "invoice_tool"
    when :contract then "contract_tool"
    when :media then "media_tool"
    when :sign then "sign_tool"
    when :down then "down_tool"
    when :open then "url_opener_tool"
    end
  end

  def page_javascript_include_tag
    return unless (entrypoint = page_javascript_entrypoint)

    javascript_include_tag entrypoint, "data-turbo-track": "reload", type: "module"
  rescue StandardError => error
    raise unless Rails.env.test? && asset_missing_error?(error)
  end

  def canonical_url
    return app_url if current_page?(root_path)

    "#{app_url}#{request.path}"
  end

  def social_title
    page_title || app_name
  end

  def social_description
    meta_description.presence || "Arolel is a free suite of everyday web utilities for files, PDFs, images, media, invoices, uptime checks, and links."
  end

  def social_image_url
    "#{app_url}#{asset_path("logo/arolel-app-icon-1024.png")}"
  end

  private

  def asset_missing_error?(error)
    if defined?(Sprockets::Rails::Helper::AssetNotFound) && error.is_a?(Sprockets::Rails::Helper::AssetNotFound)
      return true
    end

    defined?(Propshaft::MissingAssetError) && error.is_a?(Propshaft::MissingAssetError)
  end
end
