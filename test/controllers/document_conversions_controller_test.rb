require "test_helper"

class DocumentConversionsControllerTest < ActionDispatch::IntegrationTest
  test "shows document conversion form" do
    get pdf_path(op: "pdf-to-docx")

    assert_response :success
    assert_select "form[action='#{document_conversion_path(op: "pdf-to-docx")}']"
    assert_select "form[data-turbo=false]"
    assert_select "input[type=file][name=file]"
    assert_select "input[type=radio][name=layout][value=auto][checked]"
    assert_select "input[type=radio][name=layout][value=exact]"
    assert_select "input[type=radio][name=layout][value=flow]"
  end

  test "records the requested layout on the tool run" do
    post document_conversion_path(op: "pdf-to-docx"), params: { layout: "exact" }

    assert_redirected_to pdf_path(op: "pdf-to-docx")
    run = ToolRun.last
    assert_equal "failed", run.status
    assert_equal "exact", run.metadata["layout"]
  end

  test "shows word to csv conversion form" do
    get pdf_path(op: "word-to-csv")

    assert_response :success
    assert_select "form[action='#{document_conversion_path(op: "word-to-csv")}']"
    assert_includes response.body, "Convert to CSV"
  end

  test "redirects with validation error when no file is attached" do
    post document_conversion_path(op: "docx-to-pdf")

    assert_redirected_to pdf_path(op: "docx-to-pdf")
    assert_equal "failed", ToolRun.last.status
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Choose a file to convert."
  end
end
