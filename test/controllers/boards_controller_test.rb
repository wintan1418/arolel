require "test_helper"

class BoardsControllerTest < ActionDispatch::IntegrationTest
  test "show json returns board refresh payload" do
    board = Board.create!(name: "Status", hosts: [ "example.com" ])
    board.checks.create!(
      host: "example.com",
      status: "up",
      checked_at: 2.minutes.ago,
      region: "local"
    )

    get board_path(slug: board.slug, format: :json)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_includes payload["tableHtml"], "example.com"
    assert_equal({ "up" => 1, "slow" => 0, "down" => 0 }, payload["counts"])
    assert_match(/ago\z/, payload["lastCheckedRel"])
  end
end
