require "test_helper"

class DigitalSignaturesControllerTest < ActionDispatch::IntegrationTest
  PNG_DATA_URL = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

  test "create requires sign in" do
    post digital_signatures_path,
         params: { digital_signature: { name: "A", image_data: PNG_DATA_URL } },
         as: :json

    assert_response :unauthorized
    assert_equal "sign_in_required", response.parsed_body["error"]
  end

  test "create saves signature for signed in user" do
    user = users(:one)
    sign_in_as(user)

    assert_difference -> { user.digital_signatures.count }, 1 do
      post digital_signatures_path,
           params: {
             digital_signature: {
               name: "Ada Lovelace",
               source_text: "Ada Lovelace",
               style_key: "serif-flow",
               image_data: PNG_DATA_URL
             }
           },
           as: :json
    end

    assert_response :created
    assert_equal "Ada Lovelace", response.parsed_body["name"]
  end

  test "destroy deletes only current user's signature" do
    user = users(:one)
    sign_in_as(user)
    signature = user.digital_signatures.create!(name: "A", image_data: PNG_DATA_URL)

    assert_difference -> { user.digital_signatures.count }, -1 do
      delete digital_signature_path(signature)
    end

    assert_redirected_to dashboard_path
  end
end
