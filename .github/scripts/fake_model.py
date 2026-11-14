"""CI: a stand-in for the model. It speaks enough of the Messages API for Claude Code to finish one turn.

    python3 fake_model.py PORT LOG 'a command for the Bash tool'

A request that offers the Bash tool and holds no result yet is answered with a call of that tool. The request that
brings the result back is answered with the last words, DONE. Any other request gets a short text. Every request goes
into LOG, one JSON line each, with the text of the tool results in it: there the test reads what the command printed
inside the sandbox. No request leaves this machine.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, LOG, COMMAND = int(sys.argv[1]), sys.argv[2], sys.argv[3]
DONE = "KINGO-PROBE-DONE"


def texts(content):
    """The text in a message's content, which is a string or a list of blocks."""
    if isinstance(content, str):
        return [content]
    out = []
    for block in content or []:
        if isinstance(block, dict):
            if block.get("type") == "text":
                out.append(block.get("text", ""))
            elif block.get("type") == "tool_result":
                out += texts(block.get("content"))
    return out


def answer(body):
    """-> (kind, content blocks, stop reason)"""
    tools = [tool.get("name") for tool in body.get("tools") or []]
    results = [text for message in body.get("messages") or [] if message.get("role") == "user"
               for block in (message.get("content") if isinstance(message.get("content"), list) else [])
               if isinstance(block, dict) and block.get("type") == "tool_result" for text in texts([block])]
    if results:
        return "last words", [{"type": "text", "text": DONE}], "end_turn", results
    if "Bash" in tools:
        call = {"type": "tool_use", "id": "toolu_kingo_ci_1", "name": "Bash",
                "input": {"command": COMMAND, "description": "Run the probe of the CI"}}
        return "tool call", [call], "tool_use", results
    return "short text", [{"type": "text", "text": "ok"}], "end_turn", results


def events(model, blocks, stop):
    """The answer as the events of a stream."""
    def event(name, data):
        return "event: %s\ndata: %s\n\n" % (name, json.dumps(dict(type=name, **data)))
    usage = {"input_tokens": 10, "output_tokens": 1, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}
    out = event("message_start", {"message": {
        "id": "msg_kingo_ci", "type": "message", "role": "assistant", "model": model, "content": [],
        "stop_reason": None, "stop_sequence": None, "usage": usage}})
    for index, block in enumerate(blocks):
        if block["type"] == "text":
            out += event("content_block_start", {"index": index, "content_block": {"type": "text", "text": ""}})
            out += event("content_block_delta", {"index": index, "delta": {"type": "text_delta", "text": block["text"]}})
        else:
            start = dict(block, input={})
            out += event("content_block_start", {"index": index, "content_block": start})
            out += event("content_block_delta", {"index": index, "delta": {
                "type": "input_json_delta", "partial_json": json.dumps(block["input"])}})
        out += event("content_block_stop", {"index": index})
    out += event("message_delta", {"delta": {"stop_reason": stop, "stop_sequence": None}, "usage": {"output_tokens": 12}})
    out += event("message_stop", {})
    return out


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def reply(self, status, kind, payload):
        data = payload.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)
        self.close_connection = True

    def note(self, **entry):
        with open(LOG, "a", encoding="utf-8") as log:
            log.write(json.dumps(entry) + "\n")

    def do_GET(self):
        self.note(method="GET", path=self.path)
        self.reply(404, "application/json", json.dumps({"type": "error", "error": {"type": "not_found_error", "message": "not here"}}))

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        try:
            body = json.loads(raw or b"{}")
        except ValueError:
            body = {}
        path = self.path.split("?")[0]
        if path.endswith("/count_tokens"):
            self.note(method="POST", path=self.path, kind="count")
            return self.reply(200, "application/json", json.dumps({"input_tokens": 10}))
        if not path.endswith("/v1/messages"):
            self.note(method="POST", path=self.path, kind="unknown")
            return self.reply(404, "application/json", json.dumps({"type": "error", "error": {"type": "not_found_error", "message": "not here"}}))
        kind, blocks, stop, results = answer(body)
        self.note(method="POST", path=self.path, kind=kind, model=body.get("model"), stream=bool(body.get("stream")),
                  tools=len(body.get("tools") or []), messages=len(body.get("messages") or []), results=results,
                  key=(self.headers.get("Authorization") or self.headers.get("x-api-key") or "")[:40],
                  key_header="authorization" if self.headers.get("Authorization") else "x-api-key" if self.headers.get("x-api-key") else "")
        model = body.get("model") or "stand-in"
        if body.get("stream"):
            return self.reply(200, "text/event-stream", events(model, blocks, stop))
        message = {"id": "msg_kingo_ci", "type": "message", "role": "assistant", "model": model, "content": blocks,
                   "stop_reason": stop, "stop_sequence": None, "usage": {"input_tokens": 10, "output_tokens": 12}}
        self.reply(200, "application/json", json.dumps(message))


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
