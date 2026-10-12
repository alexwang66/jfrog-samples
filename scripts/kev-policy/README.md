# KEV-aware policy gate

A pipeline stage that fails the build when a dependency appears in the
[CISA Known Exploited Vulnerabilities catalog](https://www.cisa.gov/known-exploited-vulnerabilities-catalog).

## Why this exists

Most vulnerability programmes are built on a severity threshold: escalate
everything above 9.0, queue the rest. That produces a queue ranked by *how bad
exploitation would be*, not by *whether it is happening*.

KEV inverts it. It is a list of vulnerabilities someone is already using, so
it is far smaller and far more urgent than "everything above CVSS 9".

The two signals are complementary, not competing:

| | CVSS severity | CISA KEV |
| --- | --- | --- |
| Answers | How bad would this be? | Is this being exploited now? |
| Basis | Derived score | Observed exploitation |
| Size | Tens of thousands per year | ~1,700 total |
| Response | Organisation-defined | CISA-defined due date |

A CVSS 9.8 component may never appear in KEV. A CVSS 5.3 component may already
be there. Both deserve a control; they need different controls.

## Where it sits in the pipeline

```
jf npm install                 resolve dependencies, record build info
jf rt build-publish            publish the build info to Artifactory
POST /xray/api/v1/summary/component
                               Xray reports CVEs per component
python3 kev_gate.py            cross-check those CVEs against the KEV catalog
                               -> exit 1 if any dependency is actively exploited
```

Xray supplies the component-to-CVE mapping. The gate supplies the exploitation
signal. Neither substitutes for the other.

## Files

| File | Purpose |
| --- | --- |
| `kev_gate.py` | The gate. Consumes an Xray summary and the KEV catalog, emits a report, sets the exit code. |
| `package_lock_to_components.py` | Turns `package-lock.json` into the request body for the Xray component summary API. |

## Usage

```bash
# Full path: Xray summary in, gate verdict out
python3 scripts/kev-policy/kev_gate.py \
  --xray-json xray-summary.json \
  --summary-md "$GITHUB_STEP_SUMMARY" \
  --json-out kev-result.json

# Ad-hoc: gate a list of CVE IDs
python3 scripts/kev-policy/kev_gate.py --cve-list "CVE-2021-21315,CVE-2026-106446"

# Warn mode: report hits without failing the job
python3 scripts/kev-policy/kev_gate.py --xray-json xray-summary.json --no-fail
```

Useful flags: `--kev-file` (local catalog), `--kev-cache` (cache path),
`--refresh-kev` (bypass the cache).

Exit codes: `0` no KEV hits, `1` KEV hits found, `2` input or configuration
error.

## Fail-closed by design

The gate exits non-zero when it cannot evaluate:

- Missing scan data exits `2` rather than silently passing.
- An empty Xray result is reported as *no data available*, not as *clean*.
  Xray only reports on components it has indexed, so an empty response is not
  evidence of safety.

## Scope of this sample

`npm-sample/package.json` pins two components on purpose:

| Component | CVE | CVSS | In KEV | Purpose |
| --- | --- | --- | --- | --- |
| `handlebars@4.7.9` | CVE-2026-106446 | 9.8 Critical | no | Shows a critical score that is *not* being exploited — severity policy territory |
| `systeminformation@5.3.0` | CVE-2021-21315 | 7.8 High (NVD) | **yes** | Shows a mid-severity component that *is* being exploited — this gate's territory |

The contrast is the demonstration. A severity-only policy blocks the first and
lets the second through; the KEV gate does the opposite. Both are needed.

`systeminformation` is present only as the KEV-listed counterpart. Removing it
from `package.json` will make the gate pass, which is itself a useful test.
