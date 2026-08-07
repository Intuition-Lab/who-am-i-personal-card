# Security

The beta handles owner-local personal context. Treat access to the Runtime,
MCP tools, captures, evidence receipts, exports, and `HUMAN.md` as access to
personal data.

## Report privately

Do not open a public issue for suspected credential exposure, unintended
external access, data loss, permission bypass, or leaked personal context.
Use the repository's private security-reporting channel after the new GitHub
repository is created.

Include only:

- product version and pinned Runtime commit;
- Mac architecture and macOS version;
- minimal reproduction steps;
- sanitized error text.

Never include:

- `~/.persome` or its database;
- captures, screenshots, `HUMAN.md`, exports, or evidence content;
- API keys, environment files, local bearer tokens, or OAuth data.

## Default boundary

- The Persome HTTP service remains loopback-only.
- The product must not upload Runtime data without explicit, scoped consent.
- Product code must not read or write the Runtime SQLite database directly.
- A security or data-loss issue stops the beta rollout until assessed.
