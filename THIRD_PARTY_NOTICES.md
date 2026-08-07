# Third-party notices

## Persome Personal Model Runtime

This product installs and interoperates with the open-source Persome Personal
Model Runtime:

- Repository: <https://github.com/Intuition-Lab/personal-model>
- Reviewed commit: `e1315d03cafb62418503e6d92b9e73400720fcd4`
- License: Apache License 2.0
- License text: <https://github.com/Intuition-Lab/personal-model/blob/e1315d03cafb62418503e6d92b9e73400720fcd4/LICENSE>
- Upstream notice: <https://github.com/Intuition-Lab/personal-model/blob/e1315d03cafb62418503e6d92b9e73400720fcd4/NOTICE>
- Upstream third-party notices: <https://github.com/Intuition-Lab/personal-model/blob/e1315d03cafb62418503e6d92b9e73400720fcd4/THIRD_PARTY_NOTICES>

The installer fetches the reviewed upstream source rather than copying it into
this repository. Upstream license and notice files remain present in that
source and in its built distribution.

## Product application runtime

The installer fetches the exact Node.js binary version and SHA-256 digest
recorded in `product.lock`. Node.js is distributed under the MIT license:
<https://github.com/nodejs/node/blob/v24.15.0/LICENSE>

The Personal Card installs these exact production dependencies from its lock
file:

- Ajv 8.20.0 — MIT: <https://github.com/ajv-validator/ajv/blob/v8.20.0/LICENSE>
- ajv-formats 3.0.1 — MIT:
  <https://github.com/ajv-validator/ajv-formats/blob/v3.0.1/LICENSE>

## Build-time security scanner

CI and release qualification download the pinned Gitleaks scanner identified
in `scripts/scan-secrets.sh`. Gitleaks is an Apache-2.0 licensed build-time
security tool and is not included in the product Release archive as an
executable.
