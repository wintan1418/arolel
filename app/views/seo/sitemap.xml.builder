xml.instruct!
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  @urls.each do |loc, changefreq, priority|
    xml.url do
      xml.loc loc
      xml.lastmod Date.current.iso8601
      xml.changefreq changefreq
      xml.priority priority
    end
  end
end
