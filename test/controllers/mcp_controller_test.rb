require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  setup { @token = McpToken.issue!("test-agent") }

  def rpc(method, params = {}, token: @token)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method:, params: }.to_json,
      headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
    response.parsed_body
  end

  test "refuses a missing or revoked token" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
    McpToken.update_all(revoked_at: Time.current)
    rpc("tools/list")
    assert_response :unauthorized
  end

  test "initialize and list the read-only tools" do
    assert_equal "alcove", rpc("initialize")["result"]["serverInfo"]["name"]
    names = rpc("tools/list")["result"]["tools"].map { _1["name"] }
    assert_equal %w[usage_summary character_report prompt_versions latest_evals open_reports], names
  end

  test "tools return numbers, never conversation text" do
    conversations(:member_june).messages.create!(role: "assistant", content: "A secret line about the user's sister", status: "completed")
    Report.create!(message: Message.last, kind: "user_flag", note: "private note")
    all = %w[usage_summary prompt_versions latest_evals open_reports].map { rpc("tools/call", { name: _1, arguments: {} })["result"] }
    all << rpc("tools/call", { name: "character_report", arguments: { slug: "june" } })["result"]
    all.each { assert_equal false, _1["isError"] }
    text = all.to_json
    assert_no_match "sister", text
    assert_no_match "private note", text
    assert_no_match "@example.com", text
  end

  test "unknown tool and bad arguments are errors, not crashes" do
    assert rpc("tools/call", { name: "drop_tables", arguments: {} })["error"]
    assert rpc("tools/call", { name: "character_report", arguments: { slug: "nobody" } })["result"]["isError"]
  end
end
