"""Run real Chromium DOM checks in an isolated local Edge profile (no packages)."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--edge", type=Path)
    parser.add_argument("--page", default="preview.html")
    parser.add_argument("--report", default="verification.json")
    args = parser.parse_args()
    project = Path(__file__).resolve().parent
    edge = args.edge or Path(os.environ.get("PROGRAMFILES(X86)", r"C:\Program Files (x86)")) / "Microsoft/Edge/Application/msedge.exe"
    if not edge.is_file():
        raise SystemExit("Edge not found. Use --edge with the browser executable path.")
    # Keep diagnostic files in work/logs when run from the delivered workspace.
    logs = project.parent / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    run = logs / ("claude-zh-check-" + time.strftime("%Y%m%d-%H%M%S"))
    run.mkdir(exist_ok=False)
    command = [str(edge), "--headless=new", "--disable-gpu", "--no-first-run",
               "--no-default-browser-check", "--disable-extensions",
               "--disable-background-networking", "--disable-component-update",
               "--user-data-dir=" + str(run / "edge-profile"),
               "--virtual-time-budget=6000", "--dump-dom",
               (project / args.page).as_uri()]
    result = subprocess.run(command, capture_output=True, timeout=40)
    dom = result.stdout.decode("utf-8", errors="replace")
    (run / "page.html").write_text(dom, encoding="utf-8")
    (run / "browser-stderr.log").write_bytes(result.stderr)
    passed = result.returncode == 0 and bool(re.search(r'data-test-status="passed"', dom))
    record = {"browser_dom_tests_passed": passed, "browser_exit_code": result.returncode,
              "tested_at_local": time.strftime("%Y-%m-%d %H:%M:%S"),
              "claude_live_injection_tested": False,
              "claude_live_note": "Developer mode and Console injection require user action; not performed by this test.",
              "test_artifacts": str(run)}
    (project / args.report).write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(record, ensure_ascii=False))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
