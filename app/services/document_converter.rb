require "fileutils"
require "open3"
require "securerandom"
require "timeout"
require "tmpdir"
require "zip"

class DocumentConverter
  Error = Class.new(StandardError)
  MissingDependency = Class.new(Error)
  InvalidInput = Class.new(Error)
  ConversionFailed = Class.new(Error)

  Result = Data.define(:bytes, :filename, :content_type)

  MAX_BYTES = 25.megabytes
  MAX_IMAGE_PAGES = 50
  TIMEOUT_SECONDS = 90

  DOCUMENT_EXTENSIONS = %w[.doc .docx .odt .rtf .txt].freeze
  PDF_EXTENSION = ".pdf"

  def initialize(operation:, upload:)
    @operation = operation.to_s
    @upload = upload
  end

  def call
    validate_upload!

    Dir.mktmpdir("arolel-document-conversion-") do |dir|
      input_path = write_upload(dir)

      case operation
      when "docx-to-pdf"
        convert_with_libreoffice(input_path, dir, "pdf", "#{base_name}.pdf", "application/pdf")
      when "pdf-to-docx"
        convert_with_libreoffice(input_path, dir, "docx", "#{base_name}.docx", docx_content_type)
      when "pdf-to-jpg"
        convert_pdf_to_images(input_path, dir, "jpg")
      when "pdf-to-png"
        convert_pdf_to_images(input_path, dir, "png")
      else
        raise InvalidInput, "Unsupported conversion."
      end
    end
  ensure
    upload&.rewind if upload.respond_to?(:rewind)
  end

  private

  attr_reader :operation, :upload

  def validate_upload!
    raise InvalidInput, "Choose a file to convert." if upload.blank?
    raise InvalidInput, "File is too large. Keep document conversions under #{MAX_BYTES / 1.megabyte}MB." if upload.size.to_i > MAX_BYTES

    case operation
    when "docx-to-pdf"
      raise InvalidInput, "Upload a DOC, DOCX, ODT, RTF, or TXT file." unless DOCUMENT_EXTENSIONS.include?(extension)
    when "pdf-to-docx", "pdf-to-jpg", "pdf-to-png"
      raise InvalidInput, "Upload a PDF file." unless extension == PDF_EXTENSION
    else
      raise InvalidInput, "Unsupported conversion."
    end
  end

  def write_upload(dir)
    path = File.join(dir, "input#{extension}")
    File.binwrite(path, upload.read)
    path
  end

  def convert_with_libreoffice(input_path, dir, target_format, filename, content_type)
    out_dir = File.join(dir, "out")
    FileUtils.mkdir_p(out_dir)

    run_command(
      libreoffice_path,
      "--headless",
      "--nologo",
      "--nofirststartwizard",
      "--nodefault",
      "--nolockcheck",
      "-env:UserInstallation=file://#{File.join(dir, "lo-profile")}",
      "--convert-to",
      target_format,
      "--outdir",
      out_dir,
      input_path
    )

    output_path = Dir.glob(File.join(out_dir, "*.#{target_format}")).first
    raise ConversionFailed, "The converter did not produce a #{target_format.upcase} file." unless output_path

    Result.new(File.binread(output_path), filename, content_type)
  end

  def convert_pdf_to_images(input_path, dir, image_format)
    out_prefix = File.join(dir, "page")
    args = [
      pdftoppm_path,
      "-r",
      "180",
      "-f",
      "1",
      "-l",
      MAX_IMAGE_PAGES.to_s,
      "-#{image_format == "jpg" ? "jpeg" : "png"}",
      input_path,
      out_prefix
    ]

    run_command(*args)

    files = Dir
      .glob(File.join(dir, "page-*.#{image_format == "jpg" ? "jpg" : "png"}"))
      .sort_by { |path| path[/-(\d+)\./, 1].to_i }
    raise ConversionFailed, "The converter did not produce any images." if files.empty?

    if files.one?
      Result.new(File.binread(files.first), "#{base_name}-page-1.#{image_format}", image_content_type(image_format))
    else
      Result.new(zip_files(files), "#{base_name}-pages.zip", "application/zip")
    end
  end

  def run_command(*args)
    stdout, stderr, status = Timeout.timeout(TIMEOUT_SECONDS) do
      Open3.capture3({ "HOME" => Dir.tmpdir }, *args)
    end

    return if status.success?

    message = stderr.presence || stdout.presence || "conversion command failed"
    raise ConversionFailed, message.to_s.lines.first.to_s.strip.presence || "Conversion failed."
  rescue Timeout::Error
    raise ConversionFailed, "Conversion timed out. Try a smaller file."
  end

  def zip_files(files)
    Zip::OutputStream.write_buffer do |zip|
      files.each do |path|
        zip.put_next_entry(File.basename(path))
        zip.write(File.binread(path))
      end
    end.string
  end

  def libreoffice_path
    command_path(ENV["LIBREOFFICE_PATH"].presence) ||
      command_path("soffice") ||
      command_path("libreoffice") ||
      raise(MissingDependency, "LibreOffice is not installed on this server.")
  end

  def pdftoppm_path
    command_path(ENV["PDFTOPPM_PATH"].presence) ||
      command_path("pdftoppm") ||
      raise(MissingDependency, "Poppler is not installed on this server.")
  end

  def command_path(command)
    return if command.blank?
    return command if command.include?(File::SEPARATOR) && File.executable?(command)

    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |path| File.join(path, command) }.find { |path| File.executable?(path) }
  end

  def extension
    File.extname(original_filename).downcase
  end

  def base_name
    File.basename(original_filename, ".*").parameterize.presence || "converted-#{SecureRandom.hex(4)}"
  end

  def original_filename
    upload.original_filename.to_s
  end

  def docx_content_type
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
  end

  def image_content_type(image_format)
    image_format == "jpg" ? "image/jpeg" : "image/png"
  end
end
