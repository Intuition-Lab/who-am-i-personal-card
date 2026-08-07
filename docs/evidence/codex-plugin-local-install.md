# Codex plugin local-install evidence

Date: 2026-08-07

Environment: macOS, Codex CLI `0.144.4`

Scope: repository-local marketplace discovery and plugin cache install only

## Procedure

The validation used an isolated disposable home directory, so it did not read
or change the operator's normal Codex configuration:

```bash
codex plugin marketplace add "$PRODUCT_ROOT" --json
codex plugin list --available --json
codex plugin add personal-model-context@intuition-lab --json
codex plugin list --json
```

## Observed result

- marketplace name: `intuition-lab`;
- plugin ID: `personal-model-context@intuition-lab`;
- discovered version: `0.1.0-beta.1`;
- source resolved to `plugins/personal-model-context`;
- installation policy: `AVAILABLE`;
- authentication policy: `ON_INSTALL`;
- the installed plugin was reported as enabled.

The full isolated foundation suite then passed all 91 cases, including the
mock stdio MCP handshake and the automatic-hook security boundaries.

## Remaining evidence

This is not clean-Mac or published-GitHub evidence. Release qualification still
requires installation from the immutable public/private Git tag, review and
trust of the exact hooks through `/hooks`, a real installed Runtime MCP
handshake, representative memory retrieval, and confirmation that disabling or
removing the plugin stops automatic recall.
