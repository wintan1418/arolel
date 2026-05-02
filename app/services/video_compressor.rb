require "fileutils"
require "open3"
require "timeout"

class VideoCompressor
  Error = Class.new(StandardError)
  MissingDependency = Class.new(Error)
  CompressionFailed = Class.new(Error)

  TIMEOUT_SECONDS = ENV.fetch("VIDEO_COMPRESSION_TIMEOUT_SECONDS", 900).to_i

  def initialize(video_compression)
    @video_compression = video_compression
  end

  def call
    raise CompressionFailed, "Input video is missing." unless File.exist?(video_compression.input_path)

    FileUtils.mkdir_p(output_dir)
    output_path = File.join(output_dir, "output.mp4")

    run_command(*ffmpeg_args(video_compression.input_path, output_path))

    raise CompressionFailed, "FFmpeg did not produce an output file." unless File.exist?(output_path)

    output_path
  end

  private

  attr_reader :video_compression

  def ffmpeg_args(input_path, output_path)
    [
      *priority_prefix,
      ffmpeg_path,
      "-y",
      "-i", input_path,
      "-map", "0:v:0", "-map", "0:a:0?",
      "-vf", "scale=1280:-2:force_original_aspect_ratio=decrease,format=yuv420p",
      "-c:v", "libx264",
      "-preset", ENV.fetch("VIDEO_COMPRESSION_PRESET", "veryfast"),
      "-crf", ENV.fetch("VIDEO_COMPRESSION_CRF", "32"),
      "-threads", ENV.fetch("VIDEO_COMPRESSION_THREADS", "1"),
      "-c:a", "aac", "-b:a", ENV.fetch("VIDEO_COMPRESSION_AUDIO_BITRATE", "128k"),
      "-sn", "-dn",
      "-movflags", "+faststart",
      output_path
    ]
  end

  def run_command(*args)
    stdout, stderr, status = Timeout.timeout(TIMEOUT_SECONDS) do
      Open3.capture3({ "HOME" => Dir.tmpdir }, *args)
    end

    return if status.success?

    message = stderr.presence || stdout.presence || "video compression failed"
    raise CompressionFailed, message.to_s.lines.last(5).join(" ").squish.presence || "Video compression failed."
  rescue Timeout::Error
    raise CompressionFailed, "Video compression timed out. Try a smaller or shorter file."
  end

  def priority_prefix
    prefix = []
    prefix.push(nice_path, "-n", ENV.fetch("VIDEO_COMPRESSION_NICE", "15")) if nice_path
    prefix.push(ionice_path, "-c", "3") if ionice_path
    prefix
  end

  def output_dir
    File.dirname(video_compression.input_path)
  end

  def ffmpeg_path
    command_path(ENV["FFMPEG_PATH"].presence) ||
      command_path("ffmpeg") ||
      raise(MissingDependency, "FFmpeg is not installed on this server.")
  end

  def nice_path
    command_path("nice")
  end

  def ionice_path
    command_path("ionice")
  end

  def command_path(command)
    return if command.blank?
    return command if command.include?(File::SEPARATOR) && File.executable?(command)

    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |path| File.join(path, command) }.find { |path| File.executable?(path) }
  end
end
