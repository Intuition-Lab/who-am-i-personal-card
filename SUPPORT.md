# Beta support

Start with:

```bash
MANAGEMENT_ROOT="${PERSOME_INSTALL_HOME:-$HOME/.persome}/product-management"
bash "${MANAGEMENT_ROOT}/scripts/diagnose.sh"
bash "${MANAGEMENT_ROOT}/scripts/diagnose.sh" --json
```

When reporting a problem, provide the product version, Runtime commit, macOS
version, Mac architecture, failure phase, and the JSON diagnostic. The
diagnostic intentionally excludes Runtime content and full local paths.

If installation has not completed and the management bundle does not exist
yet, run `bash install.sh --check` from the verified extracted release.

Do not upload personal model data or secrets. See `SECURITY.md` and use the
structured beta bug template for GitHub issues.
