from __future__ import annotations

import json
from dataclasses import asdict, is_dataclass
from datetime import datetime, UTC
from pathlib import Path

from sim.reference_sim import run_reference_sim


ROOT = Path.cwd()
DATA_DIR = ROOT / "sim" / "data"
RUN_DIR = DATA_DIR / "run_reports"
LATEST_PATH = DATA_DIR / "latest_report.json"


def normalize(obj):
    if is_dataclass(obj):
        return asdict(obj)
    if isinstance(obj, dict):
        return {k: normalize(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [normalize(v) for v in obj]
    return obj


def build_report() -> dict:
    result = run_reference_sim()
    ts = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
    payload = {
        "run_id": f"run-{ts}",
        "timestamp_utc": ts,
        "result": normalize(result),
    }
    return payload


def save_report(report: dict) -> Path:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    out = RUN_DIR / f"{report['run_id']}.json"
    out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    LATEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    LATEST_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    return out


def main() -> None:
    report = build_report()
    out = save_report(report)
    print(f"[ok] saved run report: {out}")
    print(f"[ok] updated latest report: {LATEST_PATH}")


if __name__ == "__main__":
    main()
