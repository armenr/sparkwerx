#!/usr/bin/env python3
"""Check authentication, tool arguments, streaming, and a synthetic tool round trip."""

import argparse
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

MODEL = "huihui-ai/Huihui-Qwen3.8-27B-abliterated"
TOOL = {
    "type": "function",
    "function": {
        "name": "web_fetch",
        "description": "Fetch the text at a URL. Use this for current web content.",
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {"url": {"type": "string"}},
            "required": ["url"],
            "additionalProperties": False,
        },
    },
}


class Client:
    def __init__(self, base, key):
        self.base = base.rstrip("/")
        self.key = key

    def request(self, path, body=None, *, auth=True):
        headers = {"Content-Type": "application/json"}
        if auth:
            headers["Authorization"] = "Bearer " + self.key
        request = urllib.request.Request(
            self.base + path,
            data=json.dumps(body).encode() if body is not None else None,
            headers=headers,
        )
        return urllib.request.urlopen(request, timeout=180)

    def chat(self, messages, *, stream=False, thinking=False, choice="auto"):
        body = {
            "model": MODEL,
            "messages": messages,
            "tools": [TOOL],
            "tool_choice": choice,
            "stream": stream,
            "max_tokens": 2048 if thinking else 512,
            "temperature": 0.2,
            "chat_template_kwargs": {"enable_thinking": thinking},
        }
        with self.request("/v1/chat/completions", body) as response:
            if not stream:
                result = json.load(response)
                return result["choices"][0]["message"], result["choices"][0]["finish_reason"]
            calls = {}
            content = ""
            finish = None
            for line in response:
                if not line.startswith(b"data: ") or line.strip() == b"data: [DONE]":
                    continue
                chunk = json.loads(line[6:])
                if not chunk.get("choices"):
                    continue
                choice = chunk["choices"][0]
                delta = choice["delta"]
                content += delta.get("content") or ""
                finish = choice.get("finish_reason") or finish
                for item in delta.get("tool_calls") or []:
                    call = calls.setdefault(
                        item["index"],
                        {"id": "", "type": "function", "function": {"name": "", "arguments": ""}},
                    )
                    if item.get("id"):
                        call["id"] += item["id"]
                    for field in ("name", "arguments"):
                        call["function"][field] += item.get("function", {}).get(field) or ""
            return {
                "role": "assistant",
                "content": content or None,
                "tool_calls": [calls[i] for i in sorted(calls)],
            }, finish


def check_call(message, finish, expected):
    calls = message.get("tool_calls") or []
    if finish != "tool_calls" or len(calls) != 1:
        raise ValueError(f"Expected exactly one tool call; finish={finish}, count={len(calls)}")
    call = calls[0]
    if not call.get("id") or call["function"]["name"] != "web_fetch":
        raise ValueError("Missing call ID or incorrect function")
    if json.loads(call["function"]["arguments"]) != {"url": expected}:
        raise ValueError("Tool arguments differ from the requested URL")
    return call


def validate(client, *, thinking=False):
    try:
        with client.request("/v1/models", auth=False):
            raise ValueError("Unauthenticated API request was accepted")
    except urllib.error.HTTPError as error:
        if error.code != 401:
            raise
    with client.request("/v1/models") as response:
        models = json.load(response)
    if MODEL not in [model["id"] for model in models["data"]]:
        raise ValueError("Expected model is not advertised")
    print("PASS: API key required; expected model advertised", flush=True)
    last = None
    for stream in (False, True):
        for suffix in (
            "robots.txt",
            "news?lang=en&limit=2",
            "a%20b",
            "robots.txt?tag=%CE%B1",
            "docs/api",
        ):
            url = "https://example.com/" + suffix
            messages = [
                {"role": "user", "content": f"Use web_fetch to fetch exactly this URL: {url}"}
            ]
            started = time.monotonic()
            message, finish = client.chat(messages, stream=stream)
            call = check_call(message, finish, url)
            last = messages, message, call
            print(
                f"PASS: {'stream' if stream else 'JSON'} tool call, {time.monotonic() - started:.1f}s",
                flush=True,
            )
    messages, message, call = last
    # This is a fixture result, not a real fetch of example.com.
    message = {key: message[key] for key in ("role", "content", "tool_calls") if key in message}
    followup = messages + [
        message,
        {
            "role": "tool",
            "tool_call_id": call["id"],
            "content": "Test fixture: the current release code is SPARK_PROBE_OK_42.",
        },
        {
            "role": "user",
            "content": "What release code did that tool return? Answer only the code.",
        },
    ]
    answer, finish = client.chat(followup)
    if answer.get("tool_calls") or "SPARK_PROBE_OK_42" not in (answer.get("content") or ""):
        raise ValueError("Tool-result round trip failed")
    print("PASS: synthetic tool result consumed and answered correctly", flush=True)
    answer, finish = client.chat(
        [
            {
                "role": "user",
                "content": "Compute 2+2 mentally. Answer only the number; no web lookup is needed.",
            }
        ]
    )
    if answer.get("tool_calls") or "4" not in (answer.get("content") or ""):
        raise ValueError("No-tool request failed")
    print("PASS: simple answer does not call a tool", flush=True)
    if thinking:
        url = "https://example.com/robots.txt"
        message, finish = client.chat(
            [{"role": "user", "content": f"Use web_fetch to fetch {url}"}], thinking=True
        )
        check_call(message, finish, url)
        print("PASS: tool extraction with thinking enabled", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument(
        "--key-file", type=Path, default=Path.home() / ".config/sparkwerx/huihui-qwen38/api.env"
    )
    parser.add_argument("--thinking", action="store_true")
    args = parser.parse_args()
    values = dict(
        line.split("=", 1) for line in args.key_file.read_text().splitlines() if "=" in line
    )
    validate(Client(args.base_url, values["VLLM_API_KEY"]), thinking=args.thinking)


if __name__ == "__main__":
    main()
