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
end
