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
end
