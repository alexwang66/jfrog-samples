#!/usr/bin/env python3
"""KEV-aware policy gate.

Xray answers "what is vulnerable". The CISA KEV catalog answers "what is being
exploited in the wild right now". This gate acts on the intersection and fails
the pipeline when a dependency is under active exploitation - regardless of its
CVSS score.

Severity thresholds and exploitation evidence are different signals. A CVSS 5.3
component can be in KEV (it is being used today); a CVSS 9.8 component may not
be (nobody has used it yet). This gate is the exploitation half.

Inputs (at least one required):
  --xray-json PATH   Xray /xray/api/v1/summary/component response, or any
                     JSON/text blob from which CVE IDs can be recovered.
  --cve-list LIST    Comma-separated CVE IDs.

Exit codes:
  0  no KEV hits
  1  KEV hits found (gate failed)
  2  input or configuration error

Stdlib only. No third-party dependencies.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import date, datetime

DEFAULT_KEV_URL = (
    "https://www.cisa.gov/sites/default/files/feeds/"
    "known_exploited_vulnerabilities.json"
)

CVE_RE = re.compile(r"CVE-\d{4}-\d{4,}", re.IGNORECASE)

# Severity ordering so we can isolate "loud but not yet exploited".
SEVERITY_ORDER = {
    "critical": 4,
    "high": 3,
    "medium": 2,
    "low": 1,
    "unknown": 0,
    "": 0,
}


def norm_cve(value: str) -> str:
    return value.strip().upper()


def extract_cves(blob) -> set[str]:
    """Recursively recover every CVE ID from an arbitrary JSON structure."""
    found: set[str] = set()

    def walk(node) -> None:
        if isinstance(node, dict):
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)
        elif isinstance(node, str):
            for match in CVE_RE.findall(node):
                found.add(norm_cve(match))

    walk(blob)
    return found


def parse_xray_summary(blob) -> tuple[list[dict], bool]:
    """Turn an Xray summary response into flat finding records.

    Returns (findings, recognized). `recognized` is False when the document is
    not an Xray summary, in which case the caller falls back to a flat CVE set.
    """
    findings: list[dict] = []

    if not isinstance(blob, dict) or "artifacts" not in blob:
        return findings, False

    for artifact in blob.get("artifacts") or []:
        general = artifact.get("general") or {}
        component = general.get("name") or general.get("component_id") or "unknown"
        version = general.get("component_id") or ""
        pkg_type = general.get("pkg_type") or ""

        for issue in artifact.get("issues") or []:
            if not isinstance(issue, dict):
                continue
            severity = (issue.get("severity") or "Unknown").strip()
            issue_id = issue.get("issue_id") or ""
            summary = (issue.get("summary") or "").strip()
            cves = [
                norm_cve(entry["cve"])
                for entry in (issue.get("cves") or [])
                if isinstance(entry, dict) and entry.get("cve")
            ]
            for cve in cves:
                findings.append(
                    {
                        "cve": cve,
                        "component": component,
                        "component_id": version,
                        "pkg_type": pkg_type,
                        "severity": severity,
                        "issue_id": issue_id,
                        "summary": summary,
                    }
                )

    return findings, True


def findings_from_cve_list(cves: set[str]) -> list[dict]:
    return [
        {
            "cve": cve,
            "component": "(unspecified)",
            "component_id": "",
            "pkg_type": "",
            "severity": "Unknown",
            "issue_id": "",
            "summary": "",
        }
        for cve in sorted(cves)
    ]


def load_kev(args) -> dict:
    """Load the KEV catalog from a local file, the cache, or the CISA feed."""
    raw = None

    if args.kev_file:
        with open(args.kev_file, "r", encoding="utf-8") as handle:
            raw = handle.read()
    else:
        cache = args.kev_cache
        if cache and os.path.exists(cache) and not args.refresh_kev:
            with open(cache, "r", encoding="utf-8") as handle:
                raw = handle.read()
        if raw is None:
            request = urllib.request.Request(
                args.kev_url,
                headers={"User-Agent": "jfrog-kev-policy-gate/1.0"},
            )
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read().decode("utf-8")
            if cache:
                os.makedirs(os.path.dirname(cache), exist_ok=True)
                with open(cache, "w", encoding="utf-8") as handle:
                    handle.write(raw)

    catalog = json.loads(raw)
    entries = catalog.get("vulnerabilities") or []
    return {
        "catalog": catalog,
        "by_cve": {norm_cve(e["cveID"]): e for e in entries if e.get("cveID")},
    }


def days_until(due: str) -> int | None:
    if not due:
        return None
    try:
        due_date = datetime.strptime(due, "%Y-%m-%d").date()
    except ValueError:
        return None
    return (due_date - date.today()).days


def md_escape(value: str) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ").strip()


def build_report(findings, kev, args) -> tuple[str, int]:
    by_cve = kev["by_cve"]
    catalog = kev["catalog"]

    hits = [f for f in findings if f["cve"] in by_cve]
    misses = [f for f in findings if f["cve"] not in by_cve]

    # De-duplicate: one row per CVE, keeping the highest severity observed.
    dedup: dict[str, dict] = {}
    for finding in hits:
        existing = dedup.get(finding["cve"])
        if existing is None:
            dedup[finding["cve"]] = dict(finding)
        else:
            if SEVERITY_ORDER.get(finding["severity"].lower(), 0) > SEVERITY_ORDER.get(
                existing["severity"].lower(), 0
            ):
                existing["severity"] = finding["severity"]
            if existing["component"] == "(unspecified)":
                existing["component"] = finding["component"]
                existing["component_id"] = finding["component_id"]
    hits = sorted(
        dedup.values(),
        key=lambda f: (-SEVERITY_ORDER.get(f["severity"].lower(), 0), f["cve"]),
    )

    loud_not_exploited = sorted(
        {
            (f["cve"], f["component"], f["severity"])
            for f in misses
            if SEVERITY_ORDER.get(f["severity"].lower(), 0) >= SEVERITY_ORDER["high"]
        },
        key=lambda row: (-SEVERITY_ORDER.get(row[2].lower(), 0), row[0]),
    )

    lines: list[str] = []
    verdict = "FAIL" if (hits and not args.no_fail) else ("WARN" if hits else "PASS")

    lines.append("## KEV-aware policy gate")
    lines.append("")
    lines.append(
        f"**Verdict: {verdict}** — {len(hits)} KEV hit(s) across "
        f"{len({f['cve'] for f in findings})} CVE(s) reported by Xray."
    )
    lines.append("")
    lines.append(
        f"KEV catalog `{catalog.get('catalogVersion', 'unknown')}` "
        f"released {catalog.get('dateReleased', 'unknown')} — "
        f"{catalog.get('count', len(by_cve))} entries."
    )
    lines.append("")

    if not findings:
        lines.append(
            "> No CVE data was supplied. An empty result is **not** a clean "
            "result — it means no upstream data was available."
        )
        lines.append("")

    if hits:
        lines.append("### Actively exploited in your dependency tree")
        lines.append("")
        lines.append(
            "| CVE | Component | Severity | Vendor / product | Added | Due | Ransomware |"
        )
        lines.append("| --- | --- | --- | --- | --- | --- | --- |")
        for finding in hits:
            entry = by_cve[finding["cve"]]
            remaining = days_until(entry.get("dueDate", ""))
            if remaining is None:
                due = entry.get("dueDate", "-")
            elif remaining < 0:
                due = f"{entry['dueDate']} (overdue)"
            else:
                due = f"{entry['dueDate']} ({remaining}d)"
            component = component_label(finding)
            lines.append(
                "| `{cve}` | {component} | {severity} | {vendor} / {product} | "
                "{added} | {due} | {ransom} |".format(
                    cve=md_escape(finding["cve"]),
                    component=md_escape(component),
                    severity=md_escape(finding["severity"]),
                    vendor=md_escape(entry.get("vendorProject", "-")),
                    product=md_escape(entry.get("product", "-")),
                    added=md_escape(entry.get("dateAdded", "-")),
                    due=md_escape(due),
                    ransom=md_escape(entry.get("knownRansomwareCampaignUse", "-")),
                )
            )
        lines.append("")
        lines.append("**Required action per KEV entry**")
        lines.append("")
        for finding in hits:
            entry = by_cve[finding["cve"]]
            action = (entry.get("requiredAction") or "-").strip()
            lines.append(f"- `{finding['cve']}` — {action}")
        lines.append("")

    if loud_not_exploited:
        lines.append("### High severity, but not in KEV")
        lines.append("")
        lines.append(
            "These carry a high or critical score yet have no confirmed "
            "exploitation. They belong behind a severity policy, not this gate."
        )
        lines.append("")
        lines.append("| CVE | Component | Severity |")
        lines.append("| --- | --- | --- |")
        for cve, component, severity in loud_not_exploited[:15]:
            lines.append(
                f"| `{md_escape(cve)}` | {md_escape(component)} | {md_escape(severity)} |"
            )
        if len(loud_not_exploited) > 15:
            lines.append(
                f"| … | _{len(loud_not_exploited) - 15} more_ | |"
            )
        lines.append("")
        lines.append(
            "The contrast is the point: severity ranks how bad exploitation "
            "would be, KEV tells you whether it is happening."
        )
        lines.append("")

    report = "\n".join(lines) + "\n"
    exit_code = 1 if (hits and not args.no_fail) else 0
    return report, exit_code


def component_label(finding: dict) -> str:
    """Render component + version for the report."""
    name = finding.get("component") or "unknown"
    cid = finding.get("component_id") or ""
    if cid and ":" in cid:
        version = cid.rsplit(":", 1)[-1]
        if version and not name.endswith(f"@{version}"):
            return f"{name}@{version}"
    return name


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fail the pipeline when a dependency is in the CISA KEV catalog."
    )
    parser.add_argument("--xray-json", help="Xray summary JSON file, or - for stdin")
    parser.add_argument("--cve-list", help="Comma-separated CVE IDs")
    parser.add_argument("--kev-file", help="Local KEV catalog JSON")
    parser.add_argument("--kev-url", default=DEFAULT_KEV_URL, help="KEV catalog URL")
    parser.add_argument(
        "--kev-cache",
        default=os.path.expanduser("~/.cache/cisa-kev/known_exploited_vulnerabilities.json"),
        help="Cache path for the downloaded catalog",
    )
    parser.add_argument("--refresh-kev", action="store_true", help="Ignore the cache")
    parser.add_argument(
        "--no-fail",
        action="store_true",
        help="Report only; never exit non-zero on hits (warn mode)",
    )
    parser.add_argument("--summary-md", help="Append the report to this file")
    parser.add_argument("--json-out", help="Write machine-readable results here")
    args = parser.parse_args()

    if not args.xray_json and not args.cve_list:
        print(
            "error: supply --xray-json or --cve-list (or both)",
            file=sys.stderr,
        )
        return 2

    findings: list[dict] = []
    cve_only: set[str] | None = None

    if args.xray_json:
        if args.xray_json == "-":
            blob = json.load(sys.stdin)
        else:
            if not os.path.exists(args.xray_json):
                print(
                    f"error: {args.xray_json} not found - no scan data to gate on. "
                    "Failing closed.",
                    file=sys.stderr,
                )
                return 2
            with open(args.xray_json, "r", encoding="utf-8") as handle:
                text = handle.read()
            try:
                blob = json.loads(text)
            except json.JSONDecodeError:
                blob = text

        parsed, recognized = parse_xray_summary(blob)
        if recognized:
            findings.extend(parsed)
        else:
            cve_only = extract_cves(blob)
            findings.extend(findings_from_cve_list(cve_only))

    if args.cve_list:
        listed = {norm_cve(c) for c in args.cve_list.split(",") if c.strip()}
        if cve_only is None:
            cve_only = set()
        cve_only |= listed
        seen = {f["cve"] for f in findings}
        findings.extend(findings_from_cve_list(listed - seen))

    try:
        kev = load_kev(args)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
        print(f"error: could not load the KEV catalog: {exc}", file=sys.stderr)
        return 2

    report, exit_code = build_report(findings, kev, args)

    print(report)

    if args.summary_md:
        with open(args.summary_md, "a", encoding="utf-8") as handle:
            handle.write(report)

    if args.json_out:
        by_cve = kev["by_cve"]
        payload = {
            "verdict": "FAIL" if exit_code else ("WARN" if any(f["cve"] in by_cve for f in findings) else "PASS"),
            "kev_catalog_version": kev["catalog"].get("catalogVersion"),
            "cve_count": len({f["cve"] for f in findings}),
            "kev_hits": sorted({f["cve"] for f in findings if f["cve"] in by_cve}),
            "findings": findings,
        }
        with open(args.json_out, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2)

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
