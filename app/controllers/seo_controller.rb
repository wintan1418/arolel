class SeoController < ApplicationController
  allow_unauthenticated_access

  def robots
    render plain: <<~ROBOTS
      User-agent: *
      Allow: /

      Sitemap: #{app_url}/sitemap.xml
    ROBOTS
  end

  def sitemap
    @urls = [
      [ root_url, "daily", "1.0" ],
      [ heic_url, "weekly", "0.9" ],
      [ url_for(controller: "pages", action: "pdf", op: "merge", only_path: false), "weekly", "0.8" ],
      [ url_for(controller: "pages", action: "pdf", op: "split", only_path: false), "weekly", "0.8" ],
      [ url_for(controller: "pages", action: "pdf", op: "rotate", only_path: false), "weekly", "0.8" ],
      [ url_for(controller: "pages", action: "pdf", op: "compress", only_path: false), "weekly", "0.8" ],
      [ url_for(controller: "pages", action: "pdf", op: "pdf-to-docx", only_path: false), "weekly", "0.9" ],
      [ url_for(controller: "pages", action: "pdf", op: "docx-to-pdf", only_path: false), "weekly", "0.9" ],
      [ url_for(controller: "pages", action: "pdf", op: "pdf-to-jpg", only_path: false), "weekly", "0.9" ],
      [ url_for(controller: "pages", action: "pdf", op: "pdf-to-png", only_path: false), "weekly", "0.9" ],
      [ image_url(op: "compress"), "weekly", "0.8" ],
      [ new_invoice_url, "weekly", "0.8" ],
      [ sign_url, "weekly", "0.8" ],
      [ media_url(op: "mp4-to-mp3"), "weekly", "0.8" ],
      [ media_url(op: "webm-to-mp4"), "weekly", "0.8" ],
      [ down_url, "weekly", "0.7" ],
      [ open_urls_url, "weekly", "0.7" ],
      [ about_url, "monthly", "0.4" ],
      [ privacy_url, "monthly", "0.4" ],
      [ changelog_url, "monthly", "0.3" ]
    ]

    render formats: :xml
  end

  private

  def app_url
    ENV.fetch("PUBLIC_URL", "https://#{ENV.fetch("PUBLIC_HOST", "arolel.com")}")
  end
end
