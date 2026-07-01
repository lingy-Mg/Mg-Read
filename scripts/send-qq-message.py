# This script sends a QQ bot private message from GitHub Actions secrets so
# the public repository does not need to store credentials in source control.
import json
import os
import sys
import urllib.error
import urllib.request


TOKEN_URL = "https://bots.qq.com/app/getAppAccessToken"
SEND_URL_TEMPLATE = "https://api.sgroup.qq.com/v2/users/{openid}/messages"


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def post_json(url: str, data: dict, headers: dict | None = None) -> dict:
    body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    request_headers = {
        "Content-Type": "application/json",
        "User-Agent": "mg-public-build-qq-notify/1.0",
    }
    if headers:
        request_headers.update(headers)

    request = urllib.request.Request(
        url=url,
        data=body,
        headers=request_headers,
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            text = response.read().decode("utf-8", errors="replace")
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as error:
        text = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {error.code}: {text}") from error


def get_access_token(app_id: str, app_secret: str) -> str:
    payload = {
        "appId": app_id,
        "clientSecret": app_secret,
    }
    response = post_json(TOKEN_URL, payload)
    token = response.get("access_token")
    if not token:
        raise RuntimeError(f"Failed to obtain QQ access token: {response}")
    return token


def send_message(content: str) -> dict:
    app_id = require_env("QQ_BOT_APP_ID")
    app_secret = require_env("QQ_BOT_APP_SECRET")
    user_openid = require_env("QQ_BOT_USER_OPENID")
    token = get_access_token(app_id, app_secret)
    url = SEND_URL_TEMPLATE.format(openid=user_openid)
    payload = {
        "msg_type": 0,
        "content": content,
    }
    headers = {
        "Authorization": f"QQBot {token}",
    }
    return post_json(url, payload, headers)


if __name__ == "__main__":
    message = " ".join(sys.argv[1:]).strip()
    if not message and not sys.stdin.isatty():
        message = sys.stdin.read().strip()
    if not message:
        message = "GitHub 构建完成"

    result = send_message(message)
    print("发送成功:", json.dumps(result, ensure_ascii=False))
