# Model Context Protocol endpoint (JSON-RPC 2.0 over HTTP POST, the "streamable HTTP" transport answering plain
# JSON), so an operations agent can read Alcove's numbers. Read-only, bearer token (McpToken), tools in Mcp::Tools.
class McpController < ActionController::API
  PROTOCOL = "2025-06-18"

  before_action :authenticate

  def create
    request_body = JSON.parse(request.raw_post)
    return head(:accepted) if request_body["id"].nil? # notifications (e.g. notifications/initialized)

    render json: { jsonrpc: "2.0", id: request_body["id"], **answer(request_body["method"], request_body["params"] || {}) }
  rescue JSON::ParserError
    render json: { jsonrpc: "2.0", id: nil, error: { code: -32700, message: "Parse error" } }, status: :bad_request
  end

  private

  def answer(method, params)
    case method
    when "initialize"
      { result: { protocolVersion: PROTOCOL, capabilities: { tools: {} },
                  serverInfo: { name: "alcove", version: Prompts.fingerprint },
                  instructions: "Read-only numbers about Alcove (usage, cost, characters, prompt versions, evals, open reports). Never conversation text." } }
    when "ping" then { result: {} }
    when "tools/list"
      { result: { tools: Mcp::Tools::TOOLS.map { |name, tool| { name:, description: tool[:description], inputSchema: tool[:schema] } } } }
    when "tools/call"
      tool = Mcp::Tools::TOOLS[params["name"]] or return { error: { code: -32602, message: "Unknown tool #{params['name']}" } }
      data = tool[:call].call(params["arguments"] || {})
      { result: { content: [ { type: "text", text: JSON.pretty_generate(data) } ], structuredContent: data, isError: false } }
    else
      { error: { code: -32601, message: "Method not found" } }
    end
  rescue ActiveRecord::RecordNotFound, ArgumentError, TypeError => e
    { result: { content: [ { type: "text", text: e.message } ], isError: true } }
  end

  def authenticate
    token = request.authorization.to_s.delete_prefix("Bearer ").strip
    @token = McpToken.authenticate(token)
    head :unauthorized unless @token
  end
end
