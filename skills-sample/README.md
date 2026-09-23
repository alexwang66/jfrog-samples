# JFrog Skills Samples

This directory contains sample agent skills that can be validated and published to a JFrog Artifactory skills repository.

## Directory structure

Each publishable skill must be stored in its own directory and contain a `SKILL.md` file:

```text
skills-sample/
├── env-demo-malicious/
│   ├── SKILL.md
│   └── 1.0.0/
│       └── env-demo-malicious-1.0.0.zip
└── jf-publish-skills/
    └── SKILL.md
```

The `SKILL.md` YAML frontmatter must include at least `name` and `description`:

```yaml
---
name: example-skill
description: Describe what the skill does and when it should be used.
---
```

## Prerequisites

- Install JFrog CLI.
- Configure the `solenglatest` server and authenticate to it.
- Obtain the key of an Artifactory repository whose package type is `skills`.
- Ensure you have permission to deploy artifacts to that repository.

Confirm the configured server:

```bash
jf config show
```

## Validate a skill

Pass the directory containing `SKILL.md` to the validator:

```bash
python3 "${CODEX_HOME:-$HOME/.codex}/skills/.system/skill-creator/scripts/quick_validate.py" \
  skills-sample/env-demo-malicious
```

## Publish a skill

Publishing targets an Artifactory **repository key**, not a JFrog project key. Replace `<skills-repository>` with the repository assigned to your project:

```bash
jf skills publish skills-sample/env-demo-malicious \
  --server-id solenglatest \
  --repo <skills-repository> \
  --quiet
```

To publish a specific semantic version:

```bash
jf skills publish skills-sample/env-demo-malicious \
  --server-id solenglatest \
  --repo <skills-repository> \
  --version 1.0.4 \
  --quiet
```

The publish command runs its synchronous Xray scan. If the scan blocks the skill, treat the result as a security signal and verify whether the uploaded artifact remains in the repository before deciding whether to remove it.

## Optional signing

Signed skills provide evidence that installers can verify. Use a trusted PEM private key and its registered alias; never commit the private key to this repository.

```bash
jf skills publish skills-sample/env-demo-malicious \
  --server-id solenglatest \
  --repo <skills-repository> \
  --quiet \
  --signing-key /secure/path/evidence.key \
  --key-alias <trusted-key-alias>
```

Alternatively, configure `EVD_SIGNING_KEY_PATH` and `EVD_KEY_ALIAS` in the publishing environment and omit the two signing flags.

## Important safeguards

- `env-demo-malicious` is an intentionally unsafe security-testing fixture. It attempts to expose environment variables and exfiltrate `.env` data. Do not execute or publish it to a production repository; use it only in an isolated test project to verify Curation or Xray blocking behavior.
- Review every skill before publishing it, especially shell commands, network calls, and instructions that access environment variables or secret files.
- Never publish access tokens, `.env` files, private keys, or generated credential files.
- Do not overwrite an existing version automatically; publish a new semantic version or explicitly remove the old version first.
- Stop after authentication, authorization, network, or repository errors. Do not silently retry against another JFrog server or repository.
