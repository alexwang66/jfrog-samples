# AppTrust Pipeline Customer Walkthrough

This document explains the `apptrust-pipeline` GitHub Actions workflow in a customer-facing way. It is intended for demos, solution walkthroughs, and architecture discussions around JFrog AppTrust, Evidence, Xray, and release governance.

## 1. Executive Summary

The pipeline demonstrates how JFrog AppTrust can govern an application release from build to production by combining:

- CI build and container packaging
- Xray security validation
- SonarCloud code quality validation
- Signed evidence creation
- AppTrust application version creation
- Stage promotion from DEV to QA
- Manual production release approval through GitHub Environment

The key customer message:

> AppTrust turns CI/CD output into a governed application release record. Each application version carries signed evidence, passes policy gates, and can be promoted or blocked based on trusted metadata instead of manual checks.

## 2. Workflow Entry Points

Workflow file:

```text
.github/workflows/apptrust-pipeline.yml
```

The pipeline starts in two ways:

| Trigger | Purpose |
| --- | --- |
| `workflow_dispatch` | Manual demo or controlled release. The operator provides an application version, for example `1.0.29`. |
| `push` to `main` | Automatic release flow when AppTrust workflow, `apptrust-sample`, or `maven-sample` changes. |

The effective application version is:

```text
manual input app_version, or 1.0.<GitHub run number>
```

## 3. Main Configuration

The workflow is configured through GitHub repository variables and secrets.

### JFrog Platform

| Variable / Secret | Meaning |
| --- | --- |
| `JFROG_URL_SOLENG_LATEST` | JFrog Platform URL. For this demo, it points to `https://solenglatest.jfrog.io/`. |
| `SOLENG_LATEST_TOKEN` | Access token used by JFrog CLI for AppTrust, Evidence, build-info, Xray, and Docker publishing. |
| `APPTRUST_PROJECT` | JFrog Project key. Defaults to `alex`. |
| `APPTRUST_DOCKER_REPO_DEV` | Docker repository used for the DEV artifact. Defaults to `alex-docker-dev-local`. |

### Application Identity

| Name | Value |
| --- | --- |
| AppTrust application key | `alex-maven-sample` |
| AppTrust display name | `Alex Maven Sample` |
| Build info name | `alex-maven-sample-build` |
| Docker image name | `alex-maven-sample` |
| Evidence signing key alias | `alex-maven-sample-evidence-key` |

### Quality Tooling

| Tool | Configuration |
| --- | --- |
| SonarCloud | `SONAR_PROJECT_KEY=alexwang66_jfrog-sample`, `SONAR_ORGANIZATION=alexwang66` |
| Xray | Scans the Docker image and must report no violations before security evidence is created. |

## 4. End-to-End Flow

```text
Checkout source
  |
Validate JFrog and Sonar configuration
  |
Set up JFrog CLI and verify AppTrust connectivity
  |
Build Maven application
  |
Run SonarCloud quality gate
  |
Create or confirm AppTrust application
  |
Build and push Docker image with build-info
  |
Generate GitHub build provenance attestation
  |
Publish build-info with Git metadata
  |
Run Xray Docker image scan
  |
Create AppTrust application version
  |
Prepare evidence signing key
  |
Promote version to DEV
  |
Promote version to QA
  |
Attach signed evidence:
  - GitHub build provenance attestation
  - Xray security scan
  - Sonar quality gate
  - SLSA provenance
  - Unit test result
  |
Wait for production approval
  |
Mark application version RELEASED
```

## 5. Build And Security Validation

### Maven Build

The workflow builds the Maven application in `maven-sample`:

```bash
./mvnw --batch-mode clean package
```

This creates the Java application artifact that is later packaged into a Docker image.

### SonarCloud Quality Gate

The workflow runs SonarCloud analysis on:

```text
maven-sample/src/main/java
```

It waits for the quality gate result:

```text
-Dsonar.qualitygate.wait=true
```

Customer talking point:

> Code quality is evaluated before the application version is released. The Sonar result is later attached as evidence, so release decisions can reference a durable record instead of a transient CI log.

### Xray Docker Image Scan

After the Docker image is pushed, the workflow verifies that the Docker manifest is available in Artifactory, publishes build-info to JFrog, and then scans the image:

```bash
jf docker scan "$IMAGE_REF" --project "$JF_PROJECT" --fail=false
```

The pipeline then checks the scan output. If Xray does not report a clean result, the workflow stops and refuses to create passing security evidence.

Customer talking point:

> The pipeline does not blindly create security evidence. It only creates passing Xray evidence after validating that the scan result is clean.

### TEST Policy Gate

The TEST entry gate has an AppTrust policy:

```text
alex-maven-sample-test-entry-no-cvss10
```

This policy blocks promotion into TEST when Xray reports an applicable CVSS 10 vulnerability for the AppTrust application version.

Customer talking point:

> DEV promotion proves the version was created with signed evidence. TEST promotion adds a security gate: the version cannot enter TEST if the Xray result contains a CVSS 10 issue.

## 6. AppTrust Application Version

The workflow ensures the AppTrust application exists:

```bash
jf apptrust app-create "$APP_KEY" \
  --application-name "Alex Maven Sample" \
  --project "$JF_PROJECT" \
  --business-criticality medium \
  --maturity-level production
```

Then it creates the application version:

```bash
jf apptrust version-create "$APP_KEY" "$APP_VERSION" \
  --source-type-artifacts "path=$DOCKER_REPO_DEV/$IMAGE_NAME/$APP_VERSION/manifest.json" \
  --tag "ci-<run-number>" \
  --sync
```

Customer talking point:

> AppTrust models the release as an application version, not just as a package, container, or build. This gives teams a business-level release object that can move through lifecycle stages.

## 7. Signed Evidence

The pipeline signs evidence using a private key stored in GitHub Secrets:

```text
EVIDENCE_PRIVATE_KEY
```

The key is written temporarily during the workflow and used by:

```bash
jf evd create
```

### Evidence Types

| Evidence | Predicate Type | Purpose |
| --- | --- | --- |
| GitHub build provenance attestation | GitHub Artifact Attestation | Uses GitHub OIDC to attest the container image digest; the workflow registers the attestation bundle for JFrog setup action to collect as JFrog Evidence. |
| Xray security scan | `https://jfrog.com/evidence/security-scan/v1` | Proves the release candidate passed JFrog Xray security validation. |
| Sonar quality gate | `https://sonarsource.com/quality-gate/v1` | Captures SonarCloud quality gate status, ignored condition flag, and evaluated metric conditions. |
| SLSA provenance | `https://slsa.dev/provenance/v1` | Records build origin, Git commit, workflow path, runner environment, and base image. |
| JUnit test result | `http://junit.org/test-results` | Captures Maven Surefire JUnit XML results as a consolidated test report with `provider-id` set to `junit`. |

Customer talking point:

> Evidence is signed and attached to the AppTrust application version. This makes release metadata tamper-evident and reusable by policy engines, auditors, and release managers.

## 8. Promotion Flow

The workflow promotes the AppTrust application version through stages:

```bash
jf apptrust version-promote "$APP_KEY" "$APP_VERSION" DEV --promotion-type copy --sync
jf apptrust version-promote "$APP_KEY" "$APP_VERSION" QA  --promotion-type copy --sync
```

The promotion type is:

```text
copy
```

Customer talking point:

> Promotion is not just a tag change in CI. AppTrust evaluates the application version and its evidence against stage policies before allowing the version to advance.

### TEST Entry Gate

The SolEng Latest environment includes a block policy for the `alex-maven-sample` application:

| Policy | Stage Gate | Rule |
| --- | --- | --- |
| `alex-maven-sample-test-entry-no-cvss10` | `TEST` entry gate | Block if Xray finds an applicable CVE with CVSS score exactly `10.0`. |

Customer talking point:

> The TEST gate demonstrates risk-based promotion control. A release candidate can move forward only when Xray does not report an applicable CVSS 10 vulnerability.

## 9. Production Release Gate

The final job is:

```text
release-to-prod
```

It depends on the build and QA promotion job:

```text
needs: build-and-release
```

It also uses a GitHub Environment:

```text
environment: production
```

This means GitHub can require human approval before production release.

After approval, the workflow marks the AppTrust version as released:

```bash
jf apptrust version-release "$APP_KEY" "$APP_VERSION" --sync
```

Customer talking point:

> The release can combine automated policy checks with a human approval gate. This is useful for regulated environments where production release must be controlled, reviewed, and auditable.

## 10. Policy And Gate Explanation

This pipeline is designed around three control layers:

| Layer | Control |
| --- | --- |
| CI validation | Maven build, SonarCloud quality gate, Xray scan. |
| Evidence trust | Signed evidence for security, quality, provenance, and tests. |
| Release governance | AppTrust stage promotion and production approval. |

If a policy requires specific evidence, the promotion fails until that evidence exists and satisfies the rule.

Example customer explanation:

> If TEST blocks CVSS 10 findings, AppTrust checks the Xray findings associated with the application version. If an applicable CVSS 10 vulnerability exists, promotion into TEST is blocked.

## 11. Demo Script

Use this talk track during a live customer demo.

### Step 1: Start The Release

Open GitHub Actions and run:

```text
apptrust-pipeline
```

Provide a SemVer application version, for example:

```text
1.0.30
```

Explain:

> We are creating a governed application version for `alex-maven-sample`. This release will build the app, scan it, attach evidence, promote it through stages, and then wait for production approval.

### Step 2: Show Build And Scan

Point to:

- Maven build
- SonarCloud scan
- Docker image push
- Build-info publication
- Xray Docker image scan

Explain:

> The pipeline creates the technical artifacts and publishes metadata to JFrog. Xray evaluates the build before AppTrust receives passing security evidence.

### Step 3: Show Evidence Creation

Point to evidence steps:

- `Generate GitHub build provenance attestation`
- `Attach Xray security-scan evidence`
- `Attach SonarQube evidence`
- `Attach SLSA provenance evidence`
- `Attach unit-test evidence`

Explain:

> These steps convert CI results into signed release evidence after the version reaches QA, so the AppTrust UI groups the evidence under the QA stage instead of Unassigned.

### Step 4: Show Promotion

Point to:

- `Promote to DEV`
- `Promote to QA`

Explain:

> Each stage promotion can evaluate policy. If required evidence is missing or a gate fails, AppTrust blocks the promotion.

### Step 5: Show Production Approval

Point to:

```text
release-to-prod
```

Explain:

> Production release is intentionally separated from QA promotion. GitHub Environment approval gives release managers a final controlled approval point.

### Step 6: Show AppTrust UI

In JFrog AppTrust, show:

- Application: `alex-maven-sample`
- Version: the selected version, for example `1.0.30`
- Evidence attached to the version
- Stage history: DEV, QA, RELEASED
- Policy decisions and gate results

Explain:

> This is the release record customers care about. It connects artifact identity, security posture, build provenance, quality checks, and approval history in one governed application view.

## 12. Customer Q&A

### Why use AppTrust if CI already passed?

CI proves a job ran. AppTrust records what was released, what evidence supports it, what policies were evaluated, and which stage the version reached.

### Why attach evidence?

Evidence makes release decisions auditable and reusable. Security, quality, provenance, and test results can be reviewed after the CI logs expire.

### What blocks promotion?

Promotion can be blocked by AppTrust policies, such as missing security evidence, failed scan results, missing provenance, or other organization-defined gates.

### Can this work with other CI tools?

Yes. The same pattern can be applied from Jenkins, GitLab CI, Azure DevOps, or other systems, as long as they can call JFrog CLI or APIs and attach evidence.

### Why is production release a separate job?

It separates automated validation from human release approval. This supports compliance, change management, and controlled production rollout.

## 13. Key Takeaways

- AppTrust creates a business-level application version for release governance.
- JFrog Evidence captures signed facts from CI/CD and external tools.
- Xray and SonarCloud results become durable release evidence.
- Stage promotion is policy-driven and auditable.
- Production release can include a human approval gate.
- The result is a governed software supply chain from build to release.
