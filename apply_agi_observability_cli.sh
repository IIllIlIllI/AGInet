#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/agi-observability-cli-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"

backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    mkdir -p "$BACKUP_DIR/$(dirname "${file#"$ROOT/"}")"
    cp "$file" "$BACKUP_DIR/${file#"$ROOT/"}"
    echo "[backup] ${file#"$ROOT/"}"
  fi
}

write_file() {
  local file="$1"
  backup_file "$file"
  mkdir -p "$(dirname "$file")"
  cat > "$file"
  echo "[write] ${file#"$ROOT/"}"
}

echo "[patch] installing AGInet observability CLI"

write_file "$ROOT/sim/observatory/run_logger.py" <<'EOF'
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
EOF

write_file "$ROOT/sim/observatory/drift_report.py" <<'EOF'
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path.cwd()
RUN_DIR = ROOT / "sim" / "data" / "run_reports"


def load_reports() -> list[dict]:
    if not RUN_DIR.exists():
        return []
    out = []
    for p in sorted(RUN_DIR.glob("run-*.json")):
        try:
            out.append(json.loads(p.read_text(encoding="utf-8")))
        except Exception:
            pass
    return out


def top_hypothesis(report: dict) -> tuple[str | None, float]:
    post = report.get("result", {}).get("posterior_by_hypothesis", {})
    if not post:
        return None, 0.0
    hid = max(post, key=post.get)
    return hid, float(post[hid])


def main() -> None:
    reports = load_reports()
    print("=== AGINET DRIFT REPORT ===")
    if len(reports) < 2:
        print("Not enough runs for drift analysis.")
        print(f"Runs available: {len(reports)}")
        return

    a = reports[-2]
    b = reports[-1]

    a_top, a_score = top_hypothesis(a)
    b_top, b_score = top_hypothesis(b)

    a_result = a.get("result", {})
    b_result = b.get("result", {})

    print(f"previous_run: {a['run_id']}")
    print(f"latest_run:   {b['run_id']}")
    print("")
    print(f"top_hypothesis: {a_top} -> {b_top}")
    print(f"top_score:      {a_score:.4f} -> {b_score:.4f}")
    print(
        f"residual_ambiguity: "
        f"{a_result.get('residual_ambiguity')} -> {b_result.get('residual_ambiguity')}"
    )
    print(
        f"sovereignty_pressure: "
        f"{a_result.get('sovereignty_pressure'):.4f} -> {b_result.get('sovereignty_pressure'):.4f}"
    )
    print(
        f"contamination_flag: "
        f"{a_result.get('contamination_flag')} -> {b_result.get('contamination_flag')}"
    )
    print(
        f"claim_graph_contradiction_density: "
        f"{a_result.get('claim_graph_summary', {}).get('contradiction_density')} -> "
        f"{b_result.get('claim_graph_summary', {}).get('contradiction_density')}"
    )


if __name__ == "__main__":
    main()
EOF

write_file "$ROOT/tools/bin/agi" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

usage() {
  cat <<'TXT'
AGInet CLI

Usage:
  tools/bin/agi doctor
  tools/bin/agi run
  tools/bin/agi observe
  tools/bin/agi drift
  tools/bin/agi graph
  tools/bin/agi graph-out
  tools/bin/agi help
TXT
}

case "${1:-help}" in
  doctor)
    bash "$ROOT/tools/bin/repo-doctor"
    ;;
  run)
    PYTHONPATH="$ROOT" python -B -m sim.reference_sim
    ;;
  observe)
    PYTHONPATH="$ROOT" python -B -m sim.observatory.run_logger
    ;;
  drift)
    PYTHONPATH="$ROOT" python -B -m sim.observatory.drift_report
    ;;
  graph)
    PYTHONPATH="$ROOT" python -B -m sim.tools.claim_graph_visualizer
    ;;
  graph-out)
    PYTHONPATH="$ROOT" python -B -m sim.tools.claim_graph_visualizer > "$ROOT/docs/generated-claim-graph.md"
    echo "[ok] wrote docs/generated-claim-graph.md"
    ;;
  help|*)
    usage
    ;;
esac
EOF

chmod +x "$ROOT/tools/bin/agi"

echo
echo "[patch] done"
echo
echo "Next steps:"
echo "  tools/bin/agi doctor"
echo "  tools/bin/agi run"
echo "  tools/bin/agi observe"
echo "  tools/bin/agi drift"
echo "  tools/bin/agi graph-out"
echo
echo "Suggested commit:"
echo '  git add tools/bin/agi sim/observatory/run_logger.py sim/observatory/drift_report.py'
echo '  git commit -m "add AGInet observability CLI"'
echo "  git push"
