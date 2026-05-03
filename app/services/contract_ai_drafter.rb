require "json"
require "net/http"
require "uri"

class ContractAiDrafter
  class NotConfigured < StandardError; end
  class DraftFailed < StandardError; end

  API_URL = "https://api.openai.com/v1/responses".freeze
  DEFAULT_MODEL = ENV.fetch("OPENAI_CONTRACT_MODEL", ENV.fetch("OPENAI_MODEL", "gpt-4o-mini"))
  MESSAGE_LIMIT = 8
  MESSAGE_SIZE_LIMIT = 1200
  SECTION_LIMIT = 10

  def initialize(template:, current_draft:, messages:, user:)
    @template = template.to_s.presence_in(%w[service nda consulting]) || "service"
    @current_draft = normalize_draft(current_draft)
    @messages = normalize_messages(messages)
    @user = user
  end

  def call
    raise NotConfigured, "Set OPENAI_API_KEY to enable AI contract drafting." if api_key.blank?

    data = perform_request
    parse_response(data)
  end

  private

  attr_reader :template, :current_draft, :messages, :user

  def perform_request
    uri = URI(API_URL)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{api_key}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(request_payload)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 45) do |http|
      http.request(request)
    end

    data = JSON.parse(response.body)
    return data if response.is_a?(Net::HTTPSuccess)

    message = data.dig("error", "message").presence || "OpenAI request failed."
    raise DraftFailed, message
  rescue JSON::ParserError
    raise DraftFailed, "OpenAI returned an unreadable response."
  rescue Timeout::Error, Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError => e
    raise DraftFailed, "OpenAI request failed: #{e.class}"
  end

  def request_payload
    {
      model: DEFAULT_MODEL,
      instructions: system_instructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: user_prompt
            }
          ]
        }
      ],
      max_output_tokens: 2200,
      text: {
        format: {
          type: "json_schema",
          name: "contract_draft_payload",
          strict: true,
          schema: response_schema
        }
      }
    }
  end

  def system_instructions
    <<~TEXT
      You are a contract drafting assistant inside Arolel.
      Rewrite and improve contract drafts for small business users.
      Stay practical, neutral, and easy to read.
      Do not claim legal compliance, enforceability, notarization, or jurisdiction-specific certainty.
      Do not add e-signature workflow, witnesses, stamps, or regulatory claims unless the user explicitly asks.
      Keep the output aligned with the selected template.
      Preserve the business facts from the current draft unless the user asks to change them.
      Keep sections concise but useful. Prefer 5 to 8 sections unless the request clearly needs more.
      Return only the structured JSON matching the schema.
    TEXT
  end

  def user_prompt
    <<~TEXT
      Selected template: #{template}
      Signed-in user: #{user.email_address}

      Current contract draft JSON:
      #{JSON.pretty_generate(current_draft)}

      Recent chat messages:
      #{JSON.pretty_generate(messages)}

      Task:
      Update the contract draft based on the user's latest request while keeping the surrounding deal context coherent.
      Return a short assistant_message that explains what changed.
    TEXT
  end

  def response_schema
    {
      type: "object",
      additionalProperties: false,
      required: %w[assistant_message title summary notes sections],
      properties: {
        assistant_message: { type: "string" },
        title: { type: "string" },
        summary: { type: "string" },
        notes: { type: "string" },
        sections: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[heading body],
            properties: {
              heading: { type: "string" },
              body: { type: "string" }
            }
          }
        }
      }
    }
  end

  def parse_response(data)
    payload = JSON.parse(extract_output_text(data))
    {
      assistant_message: payload.fetch("assistant_message"),
      draft: {
        title: payload.fetch("title"),
        summary: payload.fetch("summary"),
        notes: payload.fetch("notes"),
        sections: normalize_sections(payload.fetch("sections"))
      }
    }
  rescue KeyError, JSON::ParserError
    raise DraftFailed, "OpenAI returned an invalid draft payload."
  end

  def extract_output_text(data)
    outputs = Array(data["output"])
    text = outputs.filter_map do |item|
      next unless item["type"] == "message"

      Array(item["content"]).filter_map { |content| content["text"] if content["type"] == "output_text" }.join
    end.join

    raise DraftFailed, "OpenAI returned an empty draft response." if text.blank?

    text
  end

  def normalize_draft(draft)
    data = draft.to_h
    {
      title: data["title"].to_s,
      effective_on: data["effective_on"].to_s,
      party_a_name: data["party_a_name"].to_s,
      party_a_address: data["party_a_address"].to_s,
      party_a_email: data["party_a_email"].to_s,
      party_b_name: data["party_b_name"].to_s,
      party_b_address: data["party_b_address"].to_s,
      party_b_email: data["party_b_email"].to_s,
      summary: data["summary"].to_s,
      notes: data["notes"].to_s,
      sections: normalize_sections(data["sections"])
    }
  end

  def normalize_sections(sections)
    Array(sections).first(SECTION_LIMIT).map do |section|
      {
        heading: section["heading"].to_s,
        body: section["body"].to_s
      }
    end
  end

  def normalize_messages(messages)
    Array(messages).last(MESSAGE_LIMIT).filter_map do |message|
      role = message[:role] || message["role"]
      content = (message[:content] || message["content"]).to_s.strip
      next if content.blank?
      next unless role.in?(%w[user assistant])

      {
        role: role,
        content: content.first(MESSAGE_SIZE_LIMIT)
      }
    end
  end

  def api_key
    ENV["OPENAI_API_KEY"]
  end
end
