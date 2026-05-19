from __future__ import annotations

import argparse
import json
import subprocess
import time
from collections import deque
from dataclasses import dataclass, field
from typing import Any

from flask import Flask, jsonify, request


app = Flask(__name__)


@dataclass
class RateLimiter:
    window_seconds: int = 60
    max_requests: int = 5
    events: deque[float] = field(default_factory=deque)

    def allow(self) -> bool:
        now = time.time()
        while self.events and now - self.events[0] > self.window_seconds:
            self.events.popleft()
        if len(self.events) >= self.max_requests:
            return False
        self.events.append(now)
        return True


limiter = RateLimiter()


@app.post("/api/coach/chat")
def coach_chat():
    if not limiter.allow():
        return jsonify({"error": "rate_limited"}), 429

    payload = request.get_json(silent=True) or {}
    message = str(payload.get("message", "")).strip()
    if not message:
        return jsonify({"error": "message_required"}), 400

    if request.args.get("mock") == "true":
        return jsonify(
            {
                "reply": "**建议：先减量观察。**\n\n| 明天 | 后天 |\n|---|---|\n| 轻松跑 5-8km | 看 HRV 和腿感决定 |\n\n当前上下文已收到，正式模式会交给 Hermes + running-knowledge-base。",
                "plan_patch": None,
                "tokens_used": 0,
            }
        )

    prompt = build_prompt(payload)
    try:
        reply = ask_hermes(prompt)
    except RuntimeError as exc:
        return jsonify({"error": str(exc)}), 502

    return jsonify({"reply": reply, "plan_patch": extract_plan_patch(reply), "tokens_used": None})


def build_prompt(payload: dict[str, Any]) -> str:
    context = payload.get("context") or {}
    history = payload.get("history") or []
    message = payload.get("message") or ""

    history_text = "\n".join(
        f"{item.get('role', 'user')}: {item.get('content', '')}" for item in history[-20:]
    )

    return f"""你是 HAL9000，一位基于 Steve Magness 跑步训练方法论的 AI 教练。
你必须使用 running-knowledge-base 技能中的知识来回答问题。

## 运动员当前数据
{json.dumps(context, ensure_ascii=False, indent=2)}

## 回复格式要求
1. 先给建议/表格/计划，优先一目了然
2. 再用 1-2 句简短理由
3. 用中文回复
4. 不写长篇分析
5. 如果生成训练计划，用 JSON 块包裹

## 对话历史
{history_text}

## 用户问题
{message}
"""


def ask_hermes(prompt: str) -> str:
    command = [
        "hermes",
        "ask",
        prompt,
        "--skill",
        "running-knowledge-base",
        "--no-interactive",
    ]
    completed = subprocess.run(command, text=True, capture_output=True, timeout=45, check=False)
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "Hermes command failed")
    return completed.stdout.strip()


def extract_plan_patch(reply: str) -> dict[str, Any] | None:
    marker = "```json"
    start = reply.find(marker)
    if start < 0:
        return None
    end = reply.find("```", start + len(marker))
    if end < 0:
        return None
    raw = reply[start + len(marker):end].strip()
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) and "sessions" in value else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=5055, type=int)
    args = parser.parse_args()
    app.run(host=args.host, port=args.port)


if __name__ == "__main__":
    main()
