#!/usr/bin/env python3
"""Create or update application/config.json for local-agent (no AWS resource creation)."""

from __future__ import annotations

import argparse
import json
import os
import sys

try:
    import boto3
    from botocore.exceptions import BotoCoreError, ClientError
except ImportError:
    boto3 = None  # type: ignore
    BotoCoreError = ClientError = Exception  # type: ignore

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(ROOT, "application", "config.json")
EXAMPLE_PATH = os.path.join(ROOT, "application", "config.json.example")


DEFAULTS = {
    "region": "us-west-2",
    "projectName": "local-agent",
    "default_mcp_servers": [
        "knowledge base",
        "tavily",
        "filesystem",
        "korea_weather",
    ],
    "default_skills": [
        "retrieve",
        "tavily-search",
        "memory-manager",
        "pdf",
        "docx",
        "xlsx",
        "pptx",
    ],
}


def load_existing() -> dict:
    if os.path.isfile(CONFIG_PATH):
        with open(CONFIG_PATH, encoding="utf-8") as f:
            return json.load(f)
    if os.path.isfile(EXAMPLE_PATH):
        with open(EXAMPLE_PATH, encoding="utf-8") as f:
            data = json.load(f)
        # strip placeholders
        for key in ("knowledge_base_id", "knowledge_base_name"):
            if isinstance(data.get(key), str) and data[key].startswith("<"):
                data.pop(key, None)
        return data
    return dict(DEFAULTS)


def prompt(label: str, default: str | None = None) -> str:
    suffix = f" [{default}]" if default else ""
    value = input(f"{label}{suffix}: ").strip()
    if value:
        return value
    return default or ""


def verify_aws(region: str) -> str | None:
    if boto3 is None:
        print("boto3 not installed; skip credential check", file=sys.stderr)
        return None
    try:
        sts = boto3.client("sts", region_name=region)
        ident = sts.get_caller_identity()
        account = ident.get("Account")
        print(f"AWS identity OK: account={account} arn={ident.get('Arn')}")
        return account
    except (BotoCoreError, ClientError, Exception) as e:
        print(f"WARNING: AWS credential check failed: {e}", file=sys.stderr)
        return None


def verify_kb(region: str, kb_id: str) -> bool:
    if not kb_id or boto3 is None:
        return False
    try:
        client = boto3.client("bedrock-agent", region_name=region)
        resp = client.get_knowledge_base(knowledgeBaseId=kb_id)
        name = resp.get("knowledgeBase", {}).get("name")
        print(f"Knowledge Base OK: id={kb_id} name={name}")
        return True
    except (BotoCoreError, ClientError, Exception) as e:
        print(f"WARNING: Knowledge Base check failed: {e}", file=sys.stderr)
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description="Setup local-agent config.json")
    parser.add_argument("--region", help="Bedrock region")
    parser.add_argument("--knowledge-base-id", help="Existing Knowledge Base ID")
    parser.add_argument("--knowledge-base-name", help="Knowledge Base name (optional)")
    parser.add_argument("--project-name", default="local-agent")
    parser.add_argument("--non-interactive", action="store_true")
    parser.add_argument("--skip-verify", action="store_true")
    args = parser.parse_args()

    cfg = load_existing()
    for k, v in DEFAULTS.items():
        cfg.setdefault(k, v)

    if args.non_interactive:
        if args.region:
            cfg["region"] = args.region
        if args.knowledge_base_id:
            cfg["knowledge_base_id"] = args.knowledge_base_id
        if args.knowledge_base_name:
            cfg["knowledge_base_name"] = args.knowledge_base_name
        cfg["projectName"] = args.project_name
    else:
        print("local-agent config setup (no AWS resources will be created)\n")
        cfg["region"] = prompt("AWS region", args.region or cfg.get("region", "us-west-2"))
        cfg["projectName"] = prompt(
            "projectName", args.project_name or cfg.get("projectName", "local-agent")
        )
        cfg["knowledge_base_id"] = prompt(
            "knowledge_base_id",
            args.knowledge_base_id or cfg.get("knowledge_base_id", ""),
        )
        kb_name = prompt(
            "knowledge_base_name (optional)",
            args.knowledge_base_name or cfg.get("knowledge_base_name", ""),
        )
        if kb_name:
            cfg["knowledge_base_name"] = kb_name
        elif "knowledge_base_name" in cfg and not cfg["knowledge_base_name"]:
            cfg.pop("knowledge_base_name", None)

    if not cfg.get("knowledge_base_id"):
        print(
            "WARNING: knowledge_base_id is empty; retrieve / knowledge base MCP will fail "
            "until you set it.",
            file=sys.stderr,
        )

    if not args.skip_verify:
        account = verify_aws(cfg["region"])
        if account:
            cfg["accountId"] = account
        if cfg.get("knowledge_base_id"):
            verify_kb(cfg["region"], cfg["knowledge_base_id"])

    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"\nWrote {CONFIG_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
