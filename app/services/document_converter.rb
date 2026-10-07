require "cgi"
require "fileutils"
require "nokogiri"
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
      when "word-to-csv"
        convert_word_to_csv(input_path, dir)
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
    when "word-to-csv"
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

  def convert_with_libreoffice(input_path, dir, target_format, filename, content_type, infilter: nil)
    out_dir = File.join(dir, "out")
    FileUtils.mkdir_p(out_dir)

    args = [
      libreoffice_path,
      "--headless",
      "--nologo",
      "--nofirststartwizard",
      "--nodefault",
      "--nolockcheck",
      "-env:UserInstallation=file://#{File.join(dir, "lo-profile")}"
    ]
    args << "--infilter=#{infilter}" if infilter
    args += [ "--convert-to", target_format, "--outdir", out_dir, input_path ]
    run_command(*args)

    output_path = Dir.glob(File.join(out_dir, "*.#{target_format}")).first
    raise ConversionFailed, "The converter did not produce a #{target_format.upcase} file." unless output_path

    Result.new(File.binread(output_path), filename, content_type)
  end

  # PDF -> DOCX tries three strategies, best first:
  #
  # 1. pdf2docx (PyMuPDF based). It rebuilds paragraphs, tables, multi-column
  #    layouts and background shading, so a two-column resume or an invoice
  #    comes out looking like the original and the text flows normally.
  # 2. LibreOffice Writer's PDF import. Keeps fonts and structure but places
  #    every line as its own positioned frame, which drifts and misaligns.
  # 3. pdftotext into a minimal hand-built DOCX. Text only, always opens.
  def convert_pdf_to_docx(input_path, dir)
    filename = "#{base_name}.docx"

    if (pdf2docx = pdf2docx_path)
      begin
        return convert_pdf_to_docx_with_pdf2docx(pdf2docx, input_path, dir, filename)
      rescue ConversionFailed => error
        Rails.logger.warn("[DocumentConverter] pdf2docx failed, falling back to LibreOffice: #{error.message}")
      end
    end

    begin
      return convert_with_libreoffice(input_path, dir, "docx", filename, docx_content_type, infilter: "writer_pdf_import")
    rescue ConversionFailed, MissingDependency => error
      Rails.logger.warn("[DocumentConverter] LibreOffice PDF import failed, falling back to text: #{error.message}")
    end

    text_path = File.join(dir, "extracted.txt")
    run_command(pdftotext_path, "-layout", input_path, text_path)

    text = File.read(text_path).strip
    raise ConversionFailed, "This PDF did not contain extractable text." if text.blank?

    Result.new(build_text_docx(text), filename, docx_content_type)
  end

  # Below this share of the PDF's words, pdf2docx has dropped too much (for
  # example it sometimes skips text layered over vector artwork) and the
  # LibreOffice import is the safer result.
  MIN_TEXT_COVERAGE = 0.7

  def convert_pdf_to_docx_with_pdf2docx(pdf2docx, input_path, dir, filename)
    output_path = File.join(dir, "pdf2docx-output.docx")
    run_command(pdf2docx, "convert", input_path, output_path)

    raise ConversionFailed, "pdf2docx did not produce a DOCX file." unless File.file?(output_path)
    raise ConversionFailed, "pdf2docx produced an unreadable DOCX file." unless valid_docx?(output_path)

    bytes = polish_pdf2docx_docx(File.binread(output_path))
    coverage = text_coverage(pdf_text_words(input_path, dir), docx_text_words(bytes))
    if coverage && coverage < MIN_TEXT_COVERAGE
      raise ConversionFailed, "pdf2docx kept only #{(coverage * 100).round}% of the PDF text."
    end

    Result.new(bytes, filename, docx_content_type)
  end

  # pdf2docx reproduces page geometry very literally, which hurts in Word:
  #
  # * Table rows get `hRule="exact"` heights copied from the PDF, so any text
  #   that reflows even slightly taller is clipped. `atLeast` keeps the
  #   geometry when it fits and grows the row when it does not.
  # * Text that sat on a dark shape in the PDF keeps its white colour even
  #   when the shape did not survive as cell shading, leaving invisible
  #   white-on-white runs. Those runs lose the explicit colour so Word falls
  #   back to automatic (black) text.
  def polish_pdf2docx_docx(bytes)
    rewrite_docx_document(bytes) do |doc|
      doc.xpath("//w:trHeight[@w:hRule='exact']", DOCX_NS).each { |node| node["w:hRule"] = "atLeast" }

      doc.xpath("//w:r/w:rPr/w:color[@w:val]", DOCX_NS).each do |color|
        next unless near_white?(color["w:val"])
        next if shaded_background?(color.parent.parent)

        color.remove
      end
    end
  end

  DOCX_NS = { "w" => "http://schemas.openxmlformats.org/wordprocessingml/2006/main" }.freeze

  def rewrite_docx_document(bytes)
    document_xml = nil
    entries = []
    Zip::File.open_buffer(bytes) do |zip|
      zip.each do |entry|
        next if entry.directory?

        data = entry.get_input_stream.read
        if entry.name == "word/document.xml"
          document_xml = data
        else
          entries << [ entry.name, data ]
        end
      end
    end
    return bytes if document_xml.nil?

    doc = Nokogiri::XML(document_xml) { |config| config.strict }
    yield doc

    Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("word/document.xml")
      zip.write(doc.to_xml)
      entries.each do |name, data|
        zip.put_next_entry(name)
        zip.write(data)
      end
    end.string
  rescue Zip::Error, Nokogiri::XML::SyntaxError
    bytes
  end

  def near_white?(hex)
    return false unless hex.to_s.match?(/\A[0-9a-fA-F]{6}\z/)

    hex.scan(/../).all? { |channel| channel.to_i(16) >= 0xD0 }
  end

  # True when the run sits in a shaded paragraph or table cell, where white
  # text is intentional.
  def shaded_background?(run)
    run.ancestors.each do |ancestor|
      next unless ancestor.element?

      fill = case ancestor.name
      when "p" then ancestor.at_xpath("./w:pPr/w:shd/@w:fill", DOCX_NS)&.value
      when "tc" then ancestor.at_xpath("./w:tcPr/w:shd/@w:fill", DOCX_NS)&.value
      end
      return true if fill.present? && fill != "auto" && !near_white?(fill)
    end
    false
  end

  def pdf_text_words(input_path, dir)
    text_path = File.join(dir, "coverage.txt")
    run_command(pdftotext_path, input_path, text_path)
    significant_words(File.read(text_path))
  rescue ConversionFailed, MissingDependency, Errno::ENOENT
    nil
  end

  def docx_text_words(bytes)
    Zip::File.open_buffer(bytes) do |zip|
      xml = zip.read("word/document.xml")
      return significant_words(Nokogiri::XML(xml).xpath("//w:t", DOCX_NS).map(&:text).join(" "))
    end
  rescue Zip::Error
    Set.new
  end

  def significant_words(text)
    text.to_s.downcase.scan(/[[:alnum:]]{3,}/).to_set
  end

  def text_coverage(pdf_words, docx_words)
    return nil if pdf_words.nil? || pdf_words.size < 10

    (pdf_words & docx_words).size.to_f / pdf_words.size
  end

  # Word refuses anything that is not a proper OOXML package, so make sure the
  # converter output is a zip with a main document part before sending it on.
  def valid_docx?(path)
    return false unless File.size?(path)

    Zip::File.open(path) do |zip|
      entry = zip.find_entry("word/document.xml")
      return false unless entry

      xml = entry.get_input_stream.read
      Nokogiri::XML(xml) { |config| config.strict }
      xml.include?("<w:body")
    end
  rescue Zip::Error, Nokogiri::XML::SyntaxError
    false
  end

  def convert_word_to_csv(input_path, dir)
    csv = extension == ".docx" ? extract_docx_tables_csv(input_path) : nil
    csv = text_to_csv(extract_document_text(input_path, dir)) if csv.blank?

    raise ConversionFailed, "This document did not contain extractable table or text content." if csv.blank?

    Result.new(csv, "#{base_name}.csv", "text/csv")
  end

  def extract_docx_tables_csv(input_path)
    document_xml = nil
    Zip::File.open(input_path) do |zip|
      entry = zip.find_entry("word/document.xml")
      document_xml = entry&.get_input_stream&.read
    end
    return if document_xml.blank?

    doc = Nokogiri::XML(document_xml)
    namespaces = { "w" => "http://schemas.openxmlformats.org/wordprocessingml/2006/main" }
    rows = doc.xpath("//w:tbl/w:tr", namespaces).map do |row|
      row.xpath("./w:tc", namespaces).map { |cell| cell.xpath(".//w:t", namespaces).map(&:text).join(" ").squish }
    end.reject(&:blank?)

    return if rows.blank?

    generate_csv(rows)
  rescue Zip::Error
    nil
  end

  def extract_document_text(input_path, dir)
    return File.read(input_path) if extension == ".txt"

    out_dir = File.join(dir, "text")
    FileUtils.mkdir_p(out_dir)

    run_command(
      libreoffice_path,
      "--headless",
      "--nologo",
      "--nofirststartwizard",
      "--nodefault",
      "--nolockcheck",
      "-env:UserInstallation=file://#{File.join(dir, "lo-profile-text")}",
      "--convert-to",
      "txt:Text",
      "--outdir",
      out_dir,
      input_path
    )

    output_path = Dir.glob(File.join(out_dir, "*.txt")).first
    raise ConversionFailed, "The converter did not produce a TXT file." unless output_path

    File.read(output_path)
  end

  def text_to_csv(text)
    rows = text.to_s.lines.map(&:strip).reject(&:blank?).map do |line|
      if line.include?("\t")
        line.split("\t").map(&:strip)
      elsif line.count(",").positive?
        line.split(",").map(&:strip)
      else
        [ line ]
      end
    end

    return if rows.blank?

    generate_csv(rows)
  end

  def generate_csv(rows)
    rows.map { |row| row.map { |value| csv_cell(value) }.join(",") }.join("\n") + "\n"
  end

  def csv_cell(value)
    text = value.to_s
    return text unless text.match?(/[",\r\n]/)

    "\"#{text.gsub("\"", "\"\"")}\""
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

  # Characters outside the XML 1.0 character range. pdftotext output can
  # contain form feeds and other control characters that make Word refuse
  # the file ("Illegal xml character") if they reach document.xml.
  XML_ILLEGAL_CHARS = /[^

 -퟿-�\u{10000}-\u{10FFFF}]/

  def sanitize_docx_text(text)
    text
      .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      .gsub("\f", "\n\n")
      .gsub(XML_ILLEGAL_CHARS, "")
  end

  def build_text_docx(text)
    text = sanitize_docx_text(text)
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

  def pdf2docx_path
    command_path(ENV["PDF2DOCX_PATH"].presence) || command_path("pdf2docx")
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
