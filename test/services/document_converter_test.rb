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

  test "extracts docx table rows into csv" do
    bytes = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("word/document.xml")
      zip.write <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:tbl>
              <w:tr>
                <w:tc><w:p><w:r><w:t>Name</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>Email</w:t></w:r></w:p></w:tc>
              </w:tr>
              <w:tr>
                <w:tc><w:p><w:r><w:t>Ada</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>ada@example.com</w:t></w:r></w:p></w:tc>
              </w:tr>
            </w:tbl>
          </w:body>
        </w:document>
      XML
    end.string
    upload = FakeUpload.new("contacts.docx", bytes.bytesize, bytes)
    converter = DocumentConverter.new(operation: "word-to-csv", upload: upload)

    result = converter.call

    assert_equal "contacts.csv", result.filename
    assert_equal "text/csv", result.content_type
    assert_equal "Name,Email\nAda,ada@example.com\n", result.bytes
  end

  test "converts plain text rows to csv fallback" do
    upload = FakeUpload.new("notes.txt", 19, "Name\tEmail\nAda\ta@b.test\n")
    converter = DocumentConverter.new(operation: "word-to-csv", upload: upload)

    result = converter.call

    assert_equal "notes.csv", result.filename
    assert_equal "Name,Email\nAda,a@b.test\n", result.bytes
  end
end
