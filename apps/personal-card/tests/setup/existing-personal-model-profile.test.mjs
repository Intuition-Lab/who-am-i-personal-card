import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { existingPersonalModelProfile } from "../../src/setup/existing-personal-model-profile.mjs";

test("existing Personal Model card identity is reused without onboarding", async () => {
  const persomeRoot = await mkdtemp(join(tmpdir(), "whoami-existing-profile-"));
  const profileDirectory = join(persomeRoot, "who-am-i");
  await mkdir(profileDirectory, { mode: 0o700 });
  await writeFile(
    join(profileDirectory, "profile.json"),
    JSON.stringify({
      schemaVersion: 1,
      id: "4bf9bfc0-965f-427c-ae12-7fe452b88d3d",
      displayName: "Existing Owner",
      handle: "@existing-owner",
      tagline: "Already modeled on this Mac",
      modelName: "Existing Personal Model",
    }),
    { mode: 0o600 },
  );

  const detected = await existingPersonalModelProfile({ persomeRoot });
  assert.deepEqual(detected, {
    displayName: "Existing Owner",
    handle: "existing-owner",
    tagline: "Already modeled on this Mac",
    description: "Existing Personal Model",
    origin: "existing-personal-model",
  });
});

test("unsafe legacy profile is ignored and the macOS account becomes the local identity", async () => {
  const persomeRoot = await mkdtemp(join(tmpdir(), "whoami-unsafe-profile-"));
  const profileDirectory = join(persomeRoot, "who-am-i");
  const profilePath = join(profileDirectory, "profile.json");
  await mkdir(profileDirectory, { mode: 0o700 });
  await writeFile(
    profilePath,
    JSON.stringify({ displayName: "Do Not Import", handle: "unsafe" }),
    { mode: 0o600 },
  );
  await chmod(profilePath, 0o666);

  const detected = await existingPersonalModelProfile({
    persomeRoot,
    accountUsername: "local-user",
  });
  assert.equal(detected.displayName, "local-user");
  assert.equal(detected.handle, "local-user");
  assert.equal(detected.origin, "macos-account");
});
