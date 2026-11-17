#!/usr/bin/env python3
"""
money-guard — Cost control gate for the Hermes estate.

Guards against unapproved spend/cost accumulation:
  (1) API spend — per-session cost from state.db, aggregated daily/monthly
  (2) Subscription creep — known subscription costs from config
  (3) Paid-model overuse — ratio of premium model calls vs total
  (4) Payment URL leak — vault content checked for unapproved payment links

Exits 0 on OK, 1 on warning, 2 on critical (warnings and criticals
produce structured output that the cron deliverer pushes to Eric).

Usage:
  python3 money-guard.py [--config path] [--vault path]

Typical (cron):
  python3 money-guard.py --vault /home/eric/Documents/Notes/Hemati
"""

import argparse
import csv
import json
import os
import re
import sqlite3
import sys
import time
import yaml
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

STATE_DB = "/opt/data/state.db"
DEFAULT_CONFIG = Path(__file__).parent / "money-guard-config.yaml"
VAULT = Path("/home/eric/Documents/Notes/Hemati")


def load_config(path: str) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


def check_openrouter_spend(config: dict) -> list:
    """
    Query state.db for actual API spend per session.
    Aggregates daily and monthly cost, checks against thresholds.
    Returns list of alert dicts.
    """
    alerts = []
    conn = sqlite3.connect(STATE_DB)
    conn.row_factory = sqlite3.Row

    now = time.time()
    today_start = int(datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0).timestamp())
    thirty_days_ago = today_start - 86400 * 30

    # Daily spend (today only) — use estimated_cost_usd as actual_cost_usd is not populated
    cur = conn.execute("""
        SELECT COALESCE(SUM(estimated_cost_usd), 0) as daily_cost
        FROM sessions
        WHERE started_at >= ?
    """, (today_start,))
    row = cur.fetchone()
    daily_cost = row["daily_cost"] if row else 0.0

    daily_warn = config.get("openrouter_daily_warn", 2.00)
    daily_crit = config.get("openrouter_daily_critical", 5.00)

    if daily_cost >= daily_crit:
        alerts.append({
            "level": "CRITICAL",
            "channel": "api_spend",
            "message": f"Daily API spend ${daily_cost:.2f} exceeds critical threshold ${daily_crit:.2f}"
        })
    elif daily_cost >= daily_warn:
        alerts.append({
            "level": "WARNING",
            "channel": "api_spend",
            "message": f"Daily API spend ${daily_cost:.2f} exceeds warning threshold ${daily_warn:.2f}"
        })

    # Monthly spend (last 30 days)
    cur = conn.execute("""
        SELECT COALESCE(SUM(estimated_cost_usd), 0) as monthly_cost
        FROM sessions
        WHERE started_at >= ?
    """, (thirty_days_ago,))
    row = cur.fetchone()
    monthly_cost = row["monthly_cost"] if row else 0.0

    monthly_warn = config.get("openrouter_monthly_warn", 15.00)
    monthly_crit = config.get("openrouter_monthly_critical", 30.00)

    if monthly_cost >= monthly_crit:
        alerts.append({
            "level": "CRITICAL",
            "channel": "api_spend",
            "message": f"Monthly API spend ${monthly_cost:.2f} exceeds critical threshold ${monthly_crit:.2f}"
        })
    elif monthly_cost >= monthly_warn:
        alerts.append({
            "level": "WARNING",
            "channel": "api_spend",
            "message": f"Monthly API spend ${monthly_cost:.2f} exceeds warning threshold ${monthly_warn:.2f}"
        })

    conn.close()
    return alerts


def check_paid_model_overuse(config: dict) -> list:
    """
    Check ratio of premium model sessions vs total sessions in last 7 days.
    Premium models are expensive frontier models where cheaper alternatives exist.
    """
    alerts = []
    conn = sqlite3.connect(STATE_DB)
    conn.row_factory = sqlite3.Row

    now = time.time()
    seven_days_ago = int(datetime.now(timezone.utc).timestamp()) - 86400 * 7

    premium_models = config.get("premium_models", [])

    # Total API calls in last 7 days (from session_model_usage — per-model granularity)
    cur = conn.execute("""
        SELECT COALESCE(SUM(api_call_count), 0) as total_calls,
               COALESCE(SUM(estimated_cost_usd), 0) as total_cost
        FROM session_model_usage
        WHERE last_seen >= ?
    """, (seven_days_ago,))
    row = cur.fetchone()
    total_calls = row["total_calls"] or 0
    total_cost = row["total_cost"] or 0

    if total_calls == 0:
        conn.close()
        return []  # No data yet

    # Premium model usage
    placeholders = ",".join("?" for _ in premium_models)
    cur = conn.execute(f"""
        SELECT COALESCE(SUM(api_call_count), 0) as premium_calls,
               COALESCE(SUM(estimated_cost_usd), 0) as premium_cost
        FROM session_model_usage
        WHERE last_seen >= ?
        AND model IN ({placeholders})
    """, (seven_days_ago, *premium_models))
    row = cur.fetchone()
    premium_calls = row["premium_calls"] or 0
    premium_cost = row["premium_cost"] or 0

    premium_pct = (premium_calls / total_calls) * 100 if total_calls > 0 else 0
    premium_cost_pct = (premium_cost / total_cost) * 100 if total_cost > 0 else 0

    warn_pct = config.get("paid_model_usage_warn_pct", 20.0)
    crit_pct = config.get("paid_model_usage_critical_pct", 40.0)

    # Model breakdown for report
    cur = conn.execute("""
        SELECT model, COALESCE(SUM(api_call_count), 0) as calls,
               COALESCE(SUM(estimated_cost_usd), 0) as cost
        FROM session_model_usage
        WHERE last_seen >= ?
        GROUP BY model ORDER BY cost DESC LIMIT 15
    """, (seven_days_ago,))
    model_breakdown = {row["model"]: {"calls": row["calls"], "cost": round(row["cost"], 4)} for row in cur.fetchall()}

    if premium_pct >= crit_pct:
        alerts.append({
            "level": "CRITICAL",
            "channel": "model_overuse",
            "message": f"Premium models: {premium_calls}/{total_calls} API calls ({premium_pct:.1f}%) at ${premium_cost:.4f} — exceeds critical {crit_pct}%",
            "detail": model_breakdown
        })
    elif premium_pct >= warn_pct:
        alerts.append({
            "level": "WARNING",
            "channel": "model_overuse",
            "message": f"Premium models: {premium_calls}/{total_calls} API calls ({premium_pct:.1f}%) at ${premium_cost:.4f} — exceeds warning {warn_pct}%",
            "detail": model_breakdown
        })

    conn.close()
    return alerts


def check_subscription_costs(config: dict) -> list:
    """
    Sum known subscription costs from config and check against thresholds.
    """
    alerts = []
    subs = config.get("subscriptions", {})
    total_monthly = sum(float(v) for v in subs.values())

    monthly_warn = config.get("subscription_monthly_warn", 25.00)
    monthly_crit = config.get("subscription_monthly_critical", 50.00)

    detail_lines = [f"  {name}: ${cost}" for name, cost in sorted(subs.items())]

    if total_monthly >= monthly_crit:
        alerts.append({
            "level": "CRITICAL",
            "channel": "subscriptions",
            "message": f"Monthly subscriptions ${total_monthly:.2f} exceed critical ${monthly_crit:.2f}",
            "detail": detail_lines
        })
    elif total_monthly >= monthly_warn:
        alerts.append({
            "level": "WARNING",
            "channel": "subscriptions",
            "message": f"Monthly subscriptions ${total_monthly:.2f} exceed warning ${monthly_warn:.2f}",
            "detail": detail_lines
        })

    return alerts


def check_payment_urls(config: dict) -> list:
    """
    Scan vault content for payment URLs and cross-reference against approved list.
    This is the original 4R audit finding (P0 R-1).
    """
    alerts = []
    approved = config.get("approved_payment_urls", [])
    vault_path = VAULT

    if not vault_path.exists():
        return [{
            "level": "WARNING",
            "channel": "payment_urls",
            "message": f"Vault path {vault_path} not found — skipping payment URL check"
        }]

    # Pattern: look for URLs suggesting payment/subscription/billing
    pay_pattern = re.compile(
        r'https?://[a-zA-Z0-9.-]+\.(com|io|ai|app|org|dev)/[a-zA-Z0-9._/~%-]*(?:'
        r'pay|billing|subscribe|checkout|pricing|upgrade|plan|premium|account|purchase|order|cart'
        r'|buy|payment|invoice|subscription|charge|cost|price|bill|wallet|credit'
        r')[a-zA-Z0-9._/~%-]*',
        re.IGNORECASE
    )

    unapproved_found = []

    # Scan markdown files in vault (limit to 200 files for performance)
    md_files = list(vault_path.rglob("*.md"))
    scanned = 0
    for f in md_files:
        if scanned >= 200:
            break
        try:
            text = f.read_text(errors="replace")
        except Exception:
            continue
        for match in pay_pattern.finditer(text):
            url = match.group()
            # Check if URL is on approved list
            is_approved = any(approved_url in url for approved_url in approved)
            if not is_approved:
                rel_path = f.relative_to(vault_path)
                unapproved_found.append({
                    "file": str(rel_path),
                    "url": url
                })
        scanned += 1

    if unapproved_found:
        alerts.append({
            "level": "WARNING",
            "channel": "payment_urls",
            "message": f"Found {len(unapproved_found)} unapproved payment URLs in vault content (check against approved_payment_urls in config)",
            "detail": unapproved_found
        })

    return alerts


def generate_report(alerts: list, config: dict) -> dict:
    """Generate a structured report of all checks, even when no alerts fire."""
    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "guard_version": "0.1.0",
        "alerts": alerts,
        "summary": {
            "critical": len([a for a in alerts if a["level"] == "CRITICAL"]),
            "warning": len([a for a in alerts if a["level"] == "WARNING"]),
            "ok": 0
        },
        "checks": {}
    }

    # Gather snapshot data for the report
    conn = sqlite3.connect(STATE_DB)
    conn.row_factory = sqlite3.Row
    now = time.time()
    today_start = int(datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0).timestamp())

    # API spend snapshot — use estimated_cost_usd
    cur = conn.execute("""
        SELECT COALESCE(SUM(estimated_cost_usd), 0) as daily_cost
        FROM sessions WHERE started_at >= ?
    """, (today_start,))
    daily_cost = cur.fetchone()["daily_cost"]

    cur = conn.execute("""
        SELECT COALESCE(SUM(estimated_cost_usd), 0) as monthly_cost
        FROM sessions WHERE started_at >= ?
    """, (today_start - 86400 * 30,))
    monthly_cost = cur.fetchone()["monthly_cost"]

    # Model breakdown — from session_model_usage table for richer data
    cur = conn.execute("""
        SELECT model, COUNT(DISTINCT session_id) as sessions,
               COALESCE(SUM(estimated_cost_usd), 0) as cost,
               SUM(api_call_count) as calls,
               SUM(input_tokens + output_tokens) as tokens
        FROM session_model_usage
        WHERE last_seen >= ?
        GROUP BY model ORDER BY cost DESC LIMIT 10
    """, (today_start - 86400 * 7,))
    model_usage = [{k: round(v, 4) if isinstance(v, float) else v for k, v in dict(r).items()} for r in cur.fetchall()]

    conn.close()

    report["checks"] = {
        "api_spend_daily": round(daily_cost, 2),
        "api_spend_monthly": round(monthly_cost, 2),
        "api_spend_threshold_warn": config.get("openrouter_daily_warn", 2.00),
        "api_spend_threshold_crit": config.get("openrouter_daily_critical", 5.00),
        "subscription_monthly": sum(float(v) for v in config.get("subscriptions", {}).values()),
        "subscription_monthly_threshold_warn": config.get("subscription_monthly_warn", 25.00),
        "subscription_monthly_threshold_crit": config.get("subscription_monthly_critical", 50.00),
        "model_usage_7day": model_usage,
        "premium_models_configured": config.get("premium_models", []),
        "approved_payment_url_count": len(config.get("approved_payment_urls", [])),
        "config_profile_models": config.get("profile_models", {}),
    }

    return report


def format_output(report: dict) -> str:
    """Format report for human-readable delivery to Eric."""
    lines = []
    lines.append("=== MONEY-GUARD REPORT ===")
    lines.append(f"Time: {report['timestamp']}")
    lines.append(f"Status: {report['summary']['critical']} CRITICAL, {report['summary']['warning']} WARNING")
    lines.append("")

    if report["alerts"]:
        for a in report["alerts"]:
            icon = "!" if a["level"] == "CRITICAL" else "?"
            lines.append(f"[{icon} {a['level']}] {a['channel']}: {a['message']}")
            if "detail" in a:
                detail = a["detail"]
                if isinstance(detail, dict):
                    for k, v in list(detail.items())[:8]:
                        lines.append(f"    {k}: {v}")
                elif isinstance(detail, list):
                    for d in detail[:8]:
                        lines.append(f"    {d}")
            lines.append("")
    else:
        lines.append("[OK] All checks passed — no alerts.")
        lines.append("")

    lines.append("--- Spend Snapshot ---")
    c = report["checks"]
    lines.append(f"  Daily API spend:     ${c['api_spend_daily']:.2f}")
    lines.append(f"  Monthly API spend:   ${c['api_spend_monthly']:.2f}")
    lines.append(f"  Subscription total:  ${c['subscription_monthly']:.2f}")
    lines.append("")

    if c.get("model_usage_7day"):
        lines.append("--- Model Usage (7 days, by cost) ---")
        for m in c["model_usage_7day"][:10]:
            lines.append(f"  {m['model']}: {m['sessions']} sessions, ${m['cost']:.4f}")
        lines.append("")

    lines.append("--- Profile Model Assignments ---")
    profs = c.get("config_profile_models", {})
    for p, m in profs.items():
        lines.append(f"  {p}: {m}")
    lines.append("")
    lines.append(f"Guard config: {DEFAULT_CONFIG}")
    lines.append(f"Approved payment URLs: {c['approved_payment_url_count']} on price list")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="money-guard — cost control gate")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    parser.add_argument("--vault", default=str(VAULT))
    parser.add_argument("--json", action="store_true", help="Output JSON report instead of human-readable")
    args = parser.parse_args()

    config = load_config(args.config)

    # Run all checks
    all_alerts = []
    all_alerts.extend(check_openrouter_spend(config))
    all_alerts.extend(check_subscription_costs(config))
    all_alerts.extend(check_paid_model_overuse(config))
    all_alerts.extend(check_payment_urls(config))

    report = generate_report(all_alerts, config)

    if args.json:
        print(json.dumps(report, default=str, indent=2))
    else:
        print(format_output(report))

    # Exit code: 0 = OK, 1 = warning(s), 2 = critical(s)
    if report["summary"]["critical"] > 0:
        return 2
    if report["summary"]["warning"] > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())