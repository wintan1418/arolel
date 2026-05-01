require "test_helper"

class DocumentConverterTest < ActiveSupport::TestCase
  FakeUpload = Data.define(:original_filename, :size, :data) do
    def read = data
    def rewind = nil
  end

  test "rejects unsupported document types before running external commands" do
    upload = FakeUpload.new("image.gif", 3, "GIF")
    converter = DocumentConverter.new(operation: "docx-to-pdf", upload: upload)

    error = assert_raises(DocumentConverter::InvalidInput) { converter.call }
    assert_equal "Upload a DOC, DOCX, ODT, RTF, or TXT file.", error.message
  end

  test "rejects oversized uploads before running external commands" do
    upload = FakeUpload.new("document.pdf", DocumentConverter::MAX_BYTES + 1, "")
    converter = DocumentConverter.new(operation: "pdf-to-png", upload: upload)

    error = assert_raises(DocumentConverter::InvalidInput) { converter.call }
    assert_includes error.message, "File is too large"
  end

  test "builds a valid text docx fallback" do
    upload = FakeUpload.new("document.pdf", 3, "PDF")
    converter = DocumentConverter.new(operation: "pdf-to-docx", upload: upload)
    bytes = converter.send(:build_text_docx, "Hello\nWorld\n\nArolel & friends")

    Zip::File.open_buffer(bytes) do |zip|
      assert zip.find_entry("[Content_Types].xml")
      assert zip.find_entry("_rels/.rels")
      document = zip.read("word/document.xml")
      assert_includes document, "Hello"
      assert_includes document, "<w:br/>"
      assert_includes document, "Arolel &amp; friends"
    end
  end
end
