import assert from "node:assert/strict";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { OwnerProfileStore } from "../../src/setup/owner-profile-store.mjs";

test("owner profile creates one stable local identity and survives restart", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "whoami-owner-profile-"));
  let call = 0;
  const randomBytesFn = (size) => Buffer.alloc(size, ++call);
  const store = new OwnerProfileStore({
    dataDir,
    clock: () => Date.parse("2026-08-07T02:00:00.000Z"),
    randomBytesFn,
  });

  assert.equal(await store.load(), null);
  const created = await store.save({
    displayName: "Mira",
    handle: "@mira",
    tagline: "Designing calm systems",
    description: "A field researcher and product designer.",
  });
  assert.match(created.modelId, /^local-[a-f0-9]{20}$/);
  assert.equal(created.handle, "mira");
  assert.equal(created.displayName, "Mira");
  assert.equal(created.glyph.length, 25);
  assert.equal(store.publicView().handle, "@mira");

  const restarted = new OwnerProfileStore({ dataDir });
  const loaded = await restarted.load();
  assert.equal(loaded.modelId, created.modelId);
  assert.equal(loaded.handle, "mira");

  const updated = await restarted.save({
    displayName: "Mira Chen",
    tagline: "Still designing calm systems",
  });
  assert.equal(updated.modelId, created.modelId);
  assert.equal(updated.handle, "mira");
  assert.equal(updated.displayName, "Mira Chen");
  assert.equal(
    JSON.parse(await readFile(restarted.profilePath, "utf8")).modelId,
    created.modelId,
  );
});

test("owner profile rejects unsafe or missing public identity fields", async () => {
  const dataDir = await mkdtemp(join(tmpdir(), "whoami-owner-invalid-"));
  const store = new OwnerProfileStore({ dataDir });
  await assert.rejects(
    store.save({ displayName: "" }),
    (error) => error.code === "PROFILE_NAME_REQUIRED",
  );
  await assert.rejects(
    store.save({ displayName: "Mira", handle: "../mira" }),
    (error) => error.code === "PROFILE_HANDLE_INVALID",
  );
});
