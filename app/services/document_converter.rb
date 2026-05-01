require "cgi"
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
        convert_pdf_to_docx(input_path, dir)
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

  def convert_pdf_to_docx(input_path, dir)
    convert_with_libreoffice(input_path, dir, "docx", "#{base_name}.docx", docx_content_type)
  rescue ConversionFailed
    text_path = File.join(dir, "extracted.txt")
    run_command(pdftotext_path, "-layout", input_path, text_path)

    text = File.read(text_path).strip
    raise ConversionFailed, "This PDF did not contain extractable text." if text.blank?

    Result.new(build_text_docx(text), "#{base_name}.docx", docx_content_type)
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

  def build_text_docx(text)
    Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("[Content_Types].xml")
      zip.write <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
      XML

      zip.put_next_entry("_rels/.rels")
      zip.write <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
      XML

      zip.put_next_entry("word/document.xml")
      zip.write <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            #{docx_paragraphs(text)}
            <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
          </w:body>
        </w:document>
      XML
    end.string
  end

  def docx_paragraphs(text)
    text
      .split(/\n{2,}/)
      .map { |paragraph| paragraph.lines.map(&:rstrip).reject(&:blank?).join("\n") }
      .reject(&:blank?)
      .map { |paragraph| docx_paragraph(paragraph) }
      .join
  end

  def docx_paragraph(paragraph)
    runs = CGI.escapeHTML(paragraph).split("\n").map.with_index do |line, index|
      break_tag = index.zero? ? "" : "<w:br/>"
      "#{break_tag}<w:t xml:space=\"preserve\">#{line}</w:t>"
    end.join

    "<w:p><w:r>#{runs}</w:r></w:p>"
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

  def pdftotext_path
    command_path(ENV["PDFTOTEXT_PATH"].presence) ||
      command_path("pdftotext") ||
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
