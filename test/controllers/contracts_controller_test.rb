require "test_helper"

class ContractsControllerTest < ActionDispatch::IntegrationTest
  PNG_DATA_URL = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

  test "guest can view contract maker" do
    get new_contract_path

    assert_response :success
    assert_select "h1", text: "Contract maker"
    assert_select "[data-controller='contract']"
  end

  test "create requires sign in" do
    post "#{contracts_path}.json",
         params: {
           contract: {
             title: "Service agreement",
             template: "service",
             summary: "Draft summary",
             sections: [ { heading: "Scope", body: "Do the work." } ]
           }
         },
         as: :json

    assert_response :unauthorized
    assert_equal "sign_in_required", response.parsed_body["error"]
  end

  test "signed in user can create contract" do
    user = users(:one)
    sign_in_as(user)

    assert_difference -> { user.contracts.count }, 1 do
      post "#{contracts_path}.json",
           params: {
             contract: {
                title: "Consulting agreement",
                template: "consulting",
               effective_on: Date.current.iso8601,
               party_a_name: "Arolel Studio",
               party_b_name: "Client Co",
               summary: "Consulting support for a launch sprint.",
               signer_name: "Arolel Studio",
               signer_image_data: PNG_DATA_URL,
               sections: [
                 { heading: "Services", body: "Weekly consulting calls and delivery reviews." },
                 { heading: "Fees", body: "Client pays the agreed consulting fee." }
               ]
             }
           },
           as: :json
    end

    assert_response :success
    assert_match(/\A[a-z0-9]{7}\z/, response.parsed_body["slug"])
  end

  test "signed in user can open saved contract" do
    user = users(:one)
    sign_in_as(user)
    contract = user.contracts.create!(
      title: "Mutual NDA",
      template: "nda",
      summary: "Confidential discussions.",
      sections: [ { heading: "Term", body: "Three years." } ]
    )

    get edit_contract_path(contract.slug)

    assert_response :success
    assert_select "h1", text: "Contract maker"
    assert_includes response.body, "Mutual NDA"
  end

  test "signed in user can update own contract" do
    user = users(:one)
    sign_in_as(user)
    contract = user.contracts.create!(
      title: "Service agreement",
      template: "service",
      summary: "Initial draft",
      sections: [ { heading: "Scope", body: "Initial scope." } ]
    )

    patch "#{contract_path(contract.slug)}.json",
          params: {
            contract: {
              title: "Service agreement revised",
              template: "service",
              summary: "Updated draft",
              sections: [ { heading: "Scope", body: "Revised scope." } ]
            }
          },
          as: :json

    assert_response :success
    assert_equal "Service agreement revised", contract.reload.title
    assert_equal "Updated draft", contract.summary
  end
end
