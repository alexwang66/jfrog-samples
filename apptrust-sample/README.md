# AppTrust Sample — Full Lifecycle Demo

An end-to-end walkthrough of the JFrog AppTrust lifecycle:
**build → application version → evidence attachment → multi-stage promotion → final release**.

The sample application is a minimal nginx service (`hello-service`) that returns
JSON from `/` and `/healthz`. It is packaged as a Docker image, pushed to
Artifactory, sourced into an AppTrust application version, decorated with four
signed evidence records, and promoted stage by stage into PROD.

> References
> - AppTrust docs: https://jfrog.com/help/r/jfrog-platform-administration-documentation/apptrust
> - Evidence service: https://jfrog.com/help/r/jfrog-artifactory-documentation/evidence
> - CLI reference: `jf apptrust --help`, `jf evd --help`

---

## Directory layout

```
apptrust-sample/
├── Dockerfile                 # Pure nginx image; no Node runtime
├── nginx.conf                 # JSON responses for / and /healthz
├── evidence/                  # 4 Evidence Predicate templates
│   ├── slsa-provenance.json   # SLSA v1 provenance
│   ├── unit-tests.json        # Unit-test result summary
│   ├── security-scan.json     # Xray scan summary
│   └── qa-approval.json       # Manual QA sign-off
├── scripts/                   # Run in order for the full lifecycle
│   ├── config.sh              # Central config (override every value via env vars)
│   ├── 00-init.sh             # ping, create app, generate signing key pair
│   ├── 01-build.sh            # build/push image + publish JFrog build-info
│   ├── 02-create-version.sh   # AppTrust version-create from build
│   ├── 03-attach-evidence.sh  # attach SLSA + tests + security-scan (3 records)
│   ├── 04-promote.sh          # promote DEV → QA
│   ├── 05-approve-and-release.sh # QA approval evidence → PROD → release
│   ├── 06-verify.sh           # verify evidence signatures + query promotion history
│   ├── 07-create-policy.sh    # Unified Policy that blocks TEST entry gate
│   ├── 07b-test-policy-block.sh # verify block-then-unblock behavior
│   ├── 99-cleanup.sh          # delete versions (optionally delete app)
│   └── run-all.sh             # runs the whole flow in order
└── .github/workflows/apptrust-pipeline.yml   # GitHub Actions example
```

---

## Prerequisites

| Item | Notes |
|---|---|
| `jf` CLI ≥ 2.100 | Needs both `jf apptrust` and `jf evd` |
| Docker | For building the image |
| `jq` | Validates Evidence Predicate JSON |
| **JFrog platform** with AppTrust + Evidence enabled | |
| **Access-token auth for AppTrust** | Basic auth is rejected — use `jf c add --access-token=...` or OIDC |
| **JFrog Project** | Must exist ahead of time (default: `alex`); DEV/TEST/QA/PROD stages/environments must be configured on the platform |
| **Docker repos** | One per stage, defaults follow `<project>-docker-<stage>-local` |

### One-time platform setup

In the JFrog UI:

1. **Create a Project** named `apptrust-demo` (override via the `JF_PROJECT` env var).
2. **Create three Docker local repos** and attach them to the project:
   - `apptrust-demo-docker-dev-local`
   - `apptrust-demo-docker-qa-local`
   - `apptrust-demo-docker-prod-local`
3. **Configure lifecycle stages** (Administration → AppTrust → Lifecycle):
   `DEV`, `QA`, `PROD`, and map each repo to the matching stage.

---

## Quickstart

### 1. Configure the server
```bash
jf c add my-apptrust \
  --url https://<your-tenant>.jfrog.io \
  --access-token <token> \
  --interactive=false
jf c use my-apptrust
```

### 2. (Optional) override defaults
```bash
export JF_SERVER_ID=solenglatest
export JF_PROJECT=alex
export APP_VERSION=1.0.0
export KEY_ALIAS=hello-service-evidence-key-v2
```

For the `solenglatest` demo environment used by this repository:

```bash
export JF_SERVER_ID=solenglatest
export JF_PROJECT=alex
export KEY_ALIAS=hello-service-evidence-key-v2
export APP_VERSION=2.0.0
export TEST_VERSION=2.0.1
```

`01-build.sh` detects the Docker daemon architecture automatically. Set
`DOCKER_PLATFORM` only when the demonstration requires a different target.

The Dockerfile uses the nginx image cached in
`solenglatest.jfrog.io/alex-docker/nginx:latest`. It does not install Node.

All overridable variables live in `scripts/config.sh`.

### 3. Run everything
```bash
cd apptrust-sample
./scripts/run-all.sh
```

Or step through it:

```bash
./scripts/00-init.sh              # bootstrap app + signing keys
./scripts/01-build.sh             # build & push image + publish build-info
./scripts/02-create-version.sh    # create AppTrust version (PRE_RELEASE)
./scripts/03-attach-evidence.sh   # attach provenance, test, and scan evidence
./scripts/04-promote.sh           # DEV → TEST → QA
./scripts/05-approve-and-release.sh  # QA approval → PROD → RELEASED
./scripts/06-verify.sh            # verify trusted key and released state
./scripts/07-create-policy.sh     # ensure the TEST entry security-scan policy
./scripts/07b-test-policy-block.sh # demonstrate block, attach evidence, retry
```

If the requested `APP_VERSION` tag already exists, `01-build.sh` increments the
SemVer patch component until it finds an available tag. It saves the selected
version in `.apptrust-version`; subsequent scripts read that file automatically.
`07b-test-policy-block.sh` also increments the `TEST_VERSION` patch component
when the requested application version already exists.

---

## Evidence types

Evidence is a verifiable, signed claim about a specific application version —
the SLSA supply-chain trust anchor. This sample covers four common predicates:

| Predicate Type | Purpose | When to attach |
|---|---|---|
| `https://slsa.dev/provenance/v1` | Records build source (git commit, runner, toolchain, base image) | After build completes |
| `https://jfrog.com/evidence/test-results/v1` | Unit / integration test summary | After tests pass |
| `https://jfrog.com/evidence/security-scan/v1` | Xray scan summary + policy verdict | After scan completes |
| `https://jfrog.com/evidence/approval/v1` | Manual approval (QA, security, compliance) | Between stages |

All four are signed with the same ECDSA P-256 key (generated by
`jf evd generate-key-pair`). The default key alias is
`hello-service-evidence-key-v2`. The matching public key must be uploaded to the
platform's Trusted Keys, and the local private key must belong to that exact
public key.

---

## Lifecycle diagram

```
[git commit]
     │
     ▼
  docker build         ──► apptrust-demo-docker-dev-local
     │
     ▼
 jf rt build-publish
     │
     ▼                                     ┌──────────────────┐
 jf apptrust version-create ──► PRE_RELEASE│ Attach evidence:  │
     │                                     │  • SLSA           │
     │  ◄──────────────────────────────────┤  • Tests          │
     │                                     │  • Xray scan      │
     ▼                                     └──────────────────┘
 promote DEV  ─► apptrust-demo-docker-dev-local  (promotion recorded)
     │
     ▼
 promote QA   ─► apptrust-demo-docker-qa-local
     │
     ▼
 Evidence: QA approval
     │
     ▼
 promote PROD ─► apptrust-demo-docker-prod-local
     │
     ▼
 jf apptrust version-release  ─► releaseStatus = RELEASED (immutable)
```

---

## Troubleshooting

**Q1: `jf apptrust ping` reports `does not support basic authentication`**

AppTrust only accepts access tokens. Reconfigure with `jf c add --access-token=...`
or `jf c edit`.

**Q2: `version-create` cannot find the build**

Confirm `jf rt build-publish` succeeded, and the `build-name` / `build-number`
you pass to `--source-type-builds` match exactly. Include `--project` on both
commands if the build lives under a project.

**Q3: Promotion fails because the stage does not exist**

Create the DEV/TEST/QA/PROD stages on the platform first (Administration → AppTrust
→ Lifecycle) and map each stage to its Docker repo.

**Q4: Evidence verification fails**

`00-init.sh` uploads the public key; it may take a few seconds to propagate.
If it still fails, check:
- `--key-alias` matches on both create and verify
- The private key file `.keys/evidence.key` has mode 600
- The Trusted Keys section lists `hello-service-evidence-key-v2`
- The local private key matches the public key stored under that alias; sharing
  an alias is insufficient when the key pair differs

**Q5: Cleanup**

```bash
DELETE_APPLICATION=true ./scripts/99-cleanup.sh
```

---

## CI/CD integration

See `.github/workflows/apptrust-pipeline.yml` — a full GitHub Actions example
with OIDC auth, Xray scan, evidence attachment, multi-stage promote, and a
`production` GitHub Environment as the PROD approval gate.

Required repo-level config:

- **Variables**: `JF_URL`, `JF_OIDC_PROVIDER`
- **Secrets**: `EVIDENCE_PRIVATE_KEY` (PEM contents of the signing private key)
- **Environments**: `production` (enable required reviewers to make it a real gate)
