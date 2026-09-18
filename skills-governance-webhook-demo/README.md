# Skills governance webhook demo

This project demonstrates a low-friction distribution pattern for business users:

```text
Development Git -> JFrog Skills Registry -> Xray scan event -> approval gate -> Authorized Git -> business user
```

It deliberately keeps **JFrog / Artifactory as the governed source** and makes the
Authorized Git repository a read-only distribution mirror. A business user only
needs browser access to the Authorized repository; they do not install JFrog CLI.

## What is implemented

- `development-repo/` represents the developer-owned Git repository.
- `scripts/publish-local.mjs` represents CI publishing the bundle to JFrog.
- `registry-mirror/` is a local stand-in for the versioned bundle downloaded from
  Artifactory. It is not a second authoring source.
- `src/server.mjs` receives the **JFrog Platform `xray_scan_status`** webhook.
- `config/approved-skills.json` is the explicit business approval gate.
- `authorized-repo/` is the user-facing, read-only Git distribution repository.

The webhook follows the JFrog `xray_scan_status` payload for a terminal `DONE`
event. Xray can deliver duplicate terminal events, so the receiver is idempotent.
It also deliberately does **not** treat `DONE` as an approval decision: the event
only says that scanning is finished. Promotion requires a matching, explicitly
approved artifact in `config/approved-skills.json`.

## Run the local demo

```bash
cd skills-governance-webhook-demo
cp .env.example .env
export WEBHOOK_SHARED_SECRET='replace-with-a-long-random-secret'
npm run publish:local
npm start
```

In a second terminal:

```bash
cd skills-governance-webhook-demo
export WEBHOOK_SHARED_SECRET='replace-with-a-long-random-secret'
npm run send:sample
```

The approved content and `APPROVAL.json` will appear in:

```text
authorized-repo/customer-support/1.0.0/
```

To validate the complete local promotion pipeline without opening an HTTP port:

```bash
npm run publish:local
npm run pipeline:local
```

Run the automated checks with `npm test`.

## Connect it to JFrog and Git

1. Create an Artifactory **Skills** repository and enable Xray indexing.
2. In the development repository CI job, validate and publish the skill using
   `jf skills publish <bundle> --server-id <id> --repo <skills-repository> --version <version>`.
3. Configure a JFrog Platform webhook at **Platform > Integrations > Webhooks**:
   select **Xray Scan Status**, subscribe to **Scan completed (`DONE`)**, and use
   `POST https://<promotion-service>/webhooks/xray-scan-status`.
4. Set a custom header named `X-Skills-Webhook-Secret` with a long random secret.
   Store the same secret in the promotion service's secret manager.
5. Replace the `registry-mirror` copy in `src/core.mjs` with an authenticated,
   version-pinned download from Artifactory, then commit the resulting files to
   the Authorized Git repository using a dedicated bot identity.
6. Protect the Authorized repository: only the promotion bot may write; business
   users receive read-only access.

For production, run the receiver behind HTTPS, authenticate the webhook with a
custom secret header, use a durable idempotency store, restrict the bot token to
the authorized repository, and record the Artifactory checksum in `APPROVAL.json`.

## Important behaviour

- `FAILED`, `PARTIAL`, and `NOT_SUPPORTED` scan events never promote a skill.
- `DONE` events for an artifact missing from the approval allow-list never promote.
- The source for promotion is the registry artifact, never `development-repo`.
- A real deployment should make the approval allow-list a protected repository,
  ticketing workflow, or release approval system rather than an editable file.

## JFrog prerequisites

The Platform Xray Scan Status webhook is available from **Xray 3.150.0+**. Skill
Scanning is documented as a SaaS capability and requires the applicable AI Catalog
entitlement, settings, and AI Addendum. Verify the customer's target subscription
before presenting this as a production integration.
