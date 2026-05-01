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
    when :pdf then "pdf_tool" unless @server_side_file_tool
    when :invoice then "invoice_tool"
    when :media then "media_tool"
    when :sign then "sign_tool"
    when :down then "down_tool"
    when :open then "url_opener_tool"
    end
  end
end
