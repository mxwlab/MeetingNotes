"""服务设置：安全读改写 config.local.sh，并验证 OpenAI 兼容服务。"""

import os
import re
import shlex


DEFAULT_DEEPSEEK_BASE = "https://api.deepseek.com"
DEFAULT_DEEPSEEK_MODEL = "deepseek-chat"


def apply_updates(existing_text: str, set_map: dict, unset_keys=()) -> str:
    """更新或插入 export KEY=值，删除指定键，保留其他行及顺序。"""
    unset = set(unset_keys)
    seen = set()
    out_lines = []
    for line in (existing_text or "").splitlines():
        match = re.match(r"\s*export\s+([A-Za-z_][A-Za-z0-9_]*)=", line)
        key = match.group(1) if match else None
        if key in unset:
            continue
        if key in set_map:
            out_lines.append(f"export {key}={shlex.quote(set_map[key])}")
            seen.add(key)
        else:
            out_lines.append(line)
    for key, value in set_map.items():
        if key not in seen:
            out_lines.append(f"export {key}={shlex.quote(value)}")
    return "\n".join(out_lines) + "\n"


def _atomic_write_600(path: str, text: str) -> None:
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as file:
        file.write(text)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def _read(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as file:
            return file.read()
    except OSError:
        return ""


def save_deepseek(path: str, api_key: str) -> None:
    text = apply_updates(
        _read(path),
        {"DEEPSEEK_API_KEY": api_key},
        unset_keys=("LLM_BASE_URL", "LLM_MODEL"),
    )
    _atomic_write_600(path, text)


def save_custom(path: str, base_url: str, model: str, api_key: str) -> None:
    text = apply_updates(
        _read(path),
        {
            "DEEPSEEK_API_KEY": api_key,
            "LLM_BASE_URL": base_url,
            "LLM_MODEL": model,
        },
    )
    _atomic_write_600(path, text)


def _default_client_factory(base_url: str, api_key: str):
    from openai import OpenAI

    return OpenAI(base_url=base_url, api_key=api_key)


def validate_provider(base_url, model, api_key, *, client_factory=None):
    """发送最小 chat 请求探活，返回 ``(成功, 中文原因)``。"""
    factory = client_factory or _default_client_factory
    try:
        client = factory(base_url, api_key)
        client.chat.completions.create(
            model=model,
            max_tokens=1,
            messages=[{"role": "user", "content": "hi"}],
        )
        return True, ""
    except Exception as error:
        return False, f"验证未通过：{error}"


def validate_deepseek(api_key, *, client_factory=None):
    return validate_provider(
        DEFAULT_DEEPSEEK_BASE,
        DEFAULT_DEEPSEEK_MODEL,
        api_key,
        client_factory=client_factory,
    )
