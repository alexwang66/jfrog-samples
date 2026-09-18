# Skills Management Flow

This sample demonstrates a GitHub Actions based governance flow for skill files used by non-technical business users.

## Goal

Business users should not need to install the JFrog CLI on their laptops. They only consume approved `SKILL.md` files from the authorized Git folder.

The governance flow is:

1. A developer creates or updates a skill under `skills-management-flow/develop/<skill-name>/SKILL.md`.
2. GitHub Actions publishes that skill to the JFrog Skills repository `alex-skills-local`.
3. JFrog/Xray scans the uploaded skill. If the scan blocks the publish, the workflow stops.
4. Only after the JFrog publish and scan gate succeeds, GitHub Actions copies the approved `SKILL.md` into `skills-management-flow/authorized/<skill-name>/`.
5. Business users download or sync only from `skills-management-flow/authorized/`.

## Repository Layout

```text
skills-management-flow/
  develop/
    customer-support/
      SKILL.md
  authorized/
    .gitkeep
  scripts/
    list-skill-dirs.sh
    promote-approved-skill.sh
    validate-skill.sh
```

## Required GitHub Secrets

Create these secrets in the GitHub repository or in a protected GitHub Environment:

| Secret | Purpose |
| --- | --- |
| `JF_URL` | JFrog Platform URL, for example `https://example.jfrog.io` |
| `JF_ACCESS_TOKEN` | Token with permission to publish to `alex-skills-local` |

The workflow uses `GITHUB_TOKEN` to commit the approved skill back into the same repository. The workflow permission `contents: write` is enabled for that job.

## How To Use

1. Put a skill in `skills-management-flow/develop/<skill-name>/SKILL.md`.
2. Make sure the frontmatter contains `name`, `description`, and `version`.
3. Commit and push the change.
4. GitHub Actions publishes the skill to `alex-skills-local`.
5. If the JFrog/Xray gate passes, the workflow updates `skills-management-flow/authorized/<skill-name>/`.

For a manual demo, run the workflow named **Publish and Authorize Skills** from GitHub Actions. You can provide a single skill path such as:

```text
skills-management-flow/develop/customer-support
```

## Important Notes

- The authorized folder is the business-user facing Git source.
- Business users do not run JFrog CLI commands.
- Developers must bump the skill `version` before republishing the same skill, because JFrog Skills Registry versions are immutable by default.
- `alex-skills-local` must be an Xray indexed JFrog Skills repository with the required policy/watch enabled.
