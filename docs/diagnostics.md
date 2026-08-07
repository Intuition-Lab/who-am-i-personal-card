# Privacy-safe diagnostics

Beta users can collect a small installation diagnostic for support:

```bash
MANAGEMENT_ROOT="${PERSOME_INSTALL_HOME:-$HOME/.persome}/product-management"
bash "${MANAGEMENT_ROOT}/scripts/diagnose.sh"
```

For issue forms or automated support tooling, use the stable JSON form:

```bash
bash "${MANAGEMENT_ROOT}/scripts/diagnose.sh" --json
```

Verify the installed Card, private Node runtime and app launcher separately:

```bash
bash "${MANAGEMENT_ROOT}/scripts/verify-product.sh"
```

The command does not intentionally change product configuration or Runtime
data. The installed copy remains available after the release download directory
is removed and after a preserve-data Runtime uninstall. It reports:

- product version and the first 12 characters of the expected Runtime commit;
- macOS version and Mac architecture;
- whether the product-managed Runtime installation is present, partial, or
  absent;
- whether its owner-only installation receipt and the independent virtual
  environment identity marker both exactly match `runtime.lock`;
- the installed Python package version and whether it is expected; and
- whether the installed CLI can start its help command.

It never prints or inspects captures, `HUMAN.md`, Runtime databases, model
content, prompts, exports, credentials, tokens, environment-variable values,
the username, or the full home or installation path. Runtime command output is
discarded. The CLI check receives a minimal environment and is stopped if it
does not finish within 10 seconds.

`verify-product.sh` checks only product files and versions. It also confirms
that development fixture/test directories were not copied into the production
app. It does not read the owner Profile or any Personal Model content.

## Result states and exit codes

| Exit | `status` | Meaning |
| ---: | --- | --- |
| 0 | `healthy` | Receipt, package version, and CLI match the pinned Runtime. |
| 2 | — | Command-line usage error; no diagnostic document is emitted. |
| 3 | `not_installed` | No product-managed Runtime installation artifacts were found. |
| 4 | `identity_mismatch` | Either identity marker is missing or differs from the pin, or the package version differs. |
| 5 | `unhealthy` | The expected installation exists but its package or CLI cannot be checked successfully. |
| 5 | `diagnostic_error` | Product metadata or the safe installation location could not be resolved. |
| 6 | `unsupported_platform` | This is not a supported macOS 13+ Apple Silicon or Intel configuration. |

These nonzero states are expected diagnostic outcomes, not shell crashes.
Support automation should consume the `status` field rather than parsing human
text.

## JSON contract

The JSON schema is versioned independently through `schema_version`. Example:

```json
{
  "schema_version": 1,
  "status": "healthy",
  "product_version": "0.1.0-beta.3",
  "expected_runtime_commit": "e1315d03cafb",
  "macos_version": "15.6",
  "architecture": "arm64",
  "runtime_installation": "present",
  "receipt": "match",
  "venv_identity": "match",
  "installed_package_version": "0.3.2",
  "package_version": "match",
  "cli": "starts"
}
```

`installed_package_version` is `null` when it cannot be read safely. Other
fields use fixed string states so the result remains stable for support
automation.

This diagnostic deliberately does not run `doctor`, `status`, model inspection,
or capture inspection. A support engineer may request a separate full
verification, but its output must not be pasted into a public GitHub issue
without review.
