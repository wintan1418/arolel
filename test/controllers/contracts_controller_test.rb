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

  test "draft requires sign in" do
    post draft_contract_path,
         params: {
           template: "service",
           draft: {
             title: "Contract",
             summary: "Initial summary",
             notes: "",
             sections: [ { heading: "Scope", body: "Do the work." } ]
           },
           messages: [ { role: "user", content: "Add a deposit clause." } ]
         },
         as: :json

    assert_response :unauthorized
    assert_equal "sign_in_required", response.parsed_body["error"]
  end

  test "draft returns service unavailable when openai key is missing" do
    user = users(:one)
    sign_in_as(user)

    with_env("OPENAI_API_KEY" => nil) do
      post draft_contract_path,
           params: {
             template: "service",
             draft: {
               title: "Contract",
               summary: "Initial summary",
               notes: "",
               sections: [ { heading: "Scope", body: "Do the work." } ]
             },
             messages: [ { role: "user", content: "Add a deposit clause." } ]
           },
           as: :json
    end

    assert_response :service_unavailable
    assert_equal "not_configured", response.parsed_body["error"]
  end

  test "draft returns structured ai payload for signed in user" do
    user = users(:one)
    sign_in_as(user)
    fake = Object.new
    fake.define_singleton_method(:call) do
      {
        assistant_message: "Added a payment clause and tightened confidentiality.",
        draft: {
          title: "Consulting agreement",
          summary: "Updated summary",
          notes: "Updated notes",
          sections: [
            { heading: "Services", body: "Consulting support." },
            { heading: "Payment", body: "50% upfront." }
          ]
        }
      }
    end

    with_env("OPENAI_API_KEY" => "test-key") do
      with_stubbed_ai_drafter(fake) do
        post draft_contract_path,
             params: {
               template: "consulting",
               draft: {
                 title: "Contract",
                 summary: "Initial summary",
                 notes: "",
                 sections: [ { heading: "Scope", body: "Do the work." } ]
               },
               messages: [ { role: "user", content: "Add a deposit clause." } ]
             },
             as: :json
      end
    end

    assert_response :success
    assert_equal "Added a payment clause and tightened confidentiality.", response.parsed_body["assistant_message"]
    assert_equal "Consulting agreement", response.parsed_body.dig("draft", "title")
    assert_equal 2, response.parsed_body.dig("draft", "sections").size
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

  private

  def with_env(vars)
    old = {}
    vars.each do |key, value|
      old[key] = ENV[key]
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    old.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def with_stubbed_ai_drafter(fake)
    original = ContractAiDrafter.method(:new)
    ContractAiDrafter.define_singleton_method(:new) do |*|
      fake
    end
    yield
  ensure
    ContractAiDrafter.define_singleton_method(:new, original)
  end
end
