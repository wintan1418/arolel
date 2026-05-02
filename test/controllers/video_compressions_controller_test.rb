require "test_helper"
require "tempfile"

class VideoCompressionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "create requires sign in" do
    post video_compressions_path

    assert_redirected_to new_session_path
  end

  test "signed in user can enqueue one protected video compression" do
    sign_in_as users(:one)

    assert_difference "VideoCompression.count", 1 do
      assert_enqueued_with(job: CompressVideoJob) do
        post video_compressions_path, params: { file: uploaded_video }
      end
    end

    compression = VideoCompression.last
    assert_redirected_to video_compression_path(compression)
    assert_equal "queued", compression.status
    assert_equal "clip.mp4", compression.original_filename
    assert File.exist?(compression.input_path)
  ensure
    VideoCompression.last&.purge_files!
  end

  test "user cannot queue a second active video compression" do
    user = users(:one)
    sign_in_as user
    user.video_compressions.create!(
      status: "queued",
      original_filename: "existing.mp4",
      input_bytes: 10,
      input_path: Rails.root.join("tmp", "existing.mp4").to_s
    )

    assert_no_difference "VideoCompression.count" do
      post video_compressions_path, params: { file: uploaded_video }
    end

    assert_redirected_to media_path(op: "compress-video")
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
