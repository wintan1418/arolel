class PagesController < ApplicationController
  allow_unauthenticated_access

  def home
    set_nav :home
    page_title "Arolel — everyday web utilities, no uploads"
    meta_description "HEIC to JPG, PDF merge/split, website uptime, and bulk URL opener. HEIC and PDF tools run entirely in your browser. No accounts, no tracking."
  end

  def heic
    set_nav :heic
    page_title "HEIC to JPG converter — runs in your browser · Arolel"
    meta_description "Convert HEIC photos to JPG, PNG or WebP. Works entirely in your browser — no upload, no account, unlimited files."
  end

  def pdf
    @op = params[:op]
    set_nav :pdf
    titles = {
      "merge"    => [ "Merge PDF", "Combine multiple PDFs into one, in your browser. No upload." ],
      "split"    => [ "Split PDF", "Split a PDF into separate pages. Runs on your device only." ],
      "rotate"   => [ "Rotate PDF", "Rotate PDF pages without uploading the file." ],
      "compress" => [ "Compress PDF", "Shrink a PDF in your browser. No upload, no account." ]
    }
    t, d = titles[@op]
    page_title "#{t} — runs in your browser · Arolel"
    meta_description d
  end

  def media
    @op = params[:op]
    set_nav :media
    titles = {
      "mp4-to-mp3"  => [ "MP4 to MP3",  "Extract audio from MP4 video as MP3, in your browser. No upload." ],
      "webm-to-mp4" => [ "WebM to MP4", "Convert WebM video to MP4, in your browser. No upload." ]
    }
    t, d = titles[@op]
    page_title "#{t} — runs in your browser · Arolel"
    meta_description d

    # The media tools use the single-threaded FFmpeg core for reliability.
    # Multi-threaded FFmpeg needs COOP/COEP, but those headers make browser
    # worker/WASM loading stricter and can leave the runtime stuck compiling.
  end

  def media_debug
    return head :not_found unless Rails.env.development?

    Rails.logger.info("[media-debug] #{params[:event]} #{params[:data]}")
    head :no_content
  end

  def image
    @op = params[:op]
    set_nav :images
    titles = {
      "compress" => [ "Compress images", "Shrink JPG, PNG and WebP images in your browser. No upload, no account." ]
    }
    t, d = titles[@op]
    page_title "#{t} — runs in your browser · Arolel"
    meta_description d
  end

  def about
    set_nav :about
    page_title "About — Arolel"
  end

  def privacy
    page_title "Privacy — Arolel"
  end

  def changelog
    page_title "Changelog — Arolel"
  end
end
