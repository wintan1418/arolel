require "test_helper"

class SeoControllerTest < ActionDispatch::IntegrationTest
  test "robots points crawlers to sitemap" do
    get "/robots.txt"

    assert_response :success
    assert_includes response.body, "User-agent: *"
    assert_includes response.body, "Sitemap:"
  end

  test "sitemap includes major tool urls" do
    get "/sitemap.xml"

    assert_response :success
    assert_includes response.body, "/heic-to-jpg"
    assert_includes response.body, "/pdf-to-docx"
    assert_includes response.body, "/word-to-csv"
    assert_includes response.body, "/media/mp4-to-mp3"
    assert_includes response.body, "/roadmap"
    assert_includes response.body, "/contact"
  end
end
