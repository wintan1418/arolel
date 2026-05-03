require "test_helper"
require "tempfile"

class VideoCompressionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "create requires sign in" do
    post video_compressions_path

    assert_redirected_to new_session_path
  end

  test "signed in user can enqueue one protected video compression" do
    user = users(:one)
    sign_in_as user

    assert_difference "VideoCompression.count", 1 do
      assert_enqueued_with(job: CompressVideoJob) do
        post video_compressions_path, params: { operation: "mp4-to-mp3", file: uploaded_video }
      end
    end

    compression = user.video_compressions.order(created_at: :desc).first
    assert_redirected_to video_compression_path(compression)
    assert_equal "queued", compression.status
    assert_equal "mp4-to-mp3", compression.operation
    assert_equal 0, compression.progress_percent
    assert_equal "Queued", compression.status_message
    assert_equal "clip.mp4", compression.original_filename
    assert File.exist?(compression.input_path)
  ensure
    user&.video_compressions&.order(created_at: :desc)&.first&.purge_files!
  end

  test "user cannot queue a second active video compression" do
    user = users(:one)
    sign_in_as user
    user.video_compressions.create!(
      operation: "compress-video",
      status: "queued",
      progress_percent: 0,
      original_filename: "existing.mp4",
      input_bytes: 10,
      input_path: Rails.root.join("tmp", "existing.mp4").to_s
    )

    assert_no_difference "VideoCompression.count" do
      post video_compressions_path, params: { operation: "mp4-to-mp3", file: uploaded_video }
    end

    assert_redirected_to media_path(op: "mp4-to-mp3")
  end

  test "unsupported file type redirects back to matching media tool" do
    sign_in_as users(:one)

    assert_no_difference "VideoCompression.count" do
      post video_compressions_path, params: { operation: "webm-to-mp4", file: uploaded_video }
    end

    assert_redirected_to media_path(op: "webm-to-mp4")
  end

  test "successful download deletes converted file but keeps short-lived record" do
    user = users(:one)
    sign_in_as user
    token = SecureRandom.hex(4)
    storage_dir = Rails.root.join("storage", "video_compressions", "test-download-#{token}")

    video_compression = user.video_compressions.create!(
      operation: "mp4-to-mp3",
      status: "succeeded",
      progress_percent: 100,
      status_message: "Ready to download",
      original_filename: "clip.mp4",
      input_bytes: 10,
      input_path: storage_dir.join("input.mp4").to_s,
      output_path: storage_dir.join("output.mp3").to_s,
      output_filename: "clip-audio.mp3",
      output_bytes: 12,
      expires_at: 2.hours.from_now
    )
    output_path = video_compression.output_path

    FileUtils.mkdir_p(File.dirname(video_compression.output_path))
    File.write(video_compression.output_path, "test mp3 data")

    get download_video_compression_path(video_compression)

    assert_response :success
    assert_equal "attachment; filename=\"clip-audio.mp3\"; filename*=UTF-8''clip-audio.mp3", response.headers["Content-Disposition"]
    assert VideoCompression.exists?(video_compression.id)
    video_compression.reload
    assert_nil video_compression.output_path
    assert_equal "Downloaded and removed from server", video_compression.status_message
    assert_not File.exist?(output_path)
  end

  private

  def uploaded_video
    file = Tempfile.new([ "clip", ".mp4" ])
    file.binmode
    file.write("fake mp4")
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "video/mp4", true, original_filename: "clip.mp4")
  end
end
