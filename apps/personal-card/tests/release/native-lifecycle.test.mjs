import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import test from "node:test";

const appRoot = fileURLToPath(new URL("../../", import.meta.url));
const productRoot = fileURLToPath(new URL("../../../../", import.meta.url));
const helper = path.join(appRoot, "macos/native-lifecycle-helper.sh");

const managedInfoPlist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>ai.intuition.whoami</string>
<key>WhoAmIManagedInstall</key><true/>
</dict></plist>\n`;

function runHelper(home, ...args) {
  return new Promise((resolve) => {
    const child = spawn("/bin/bash", [helper, ...args], {
      env: {
        HOME: home,
        PATH: "/usr/bin:/bin:/usr/sbin:/sbin",
      },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    child.stdout.on("data", (chunk) => { output += chunk; });
    child.stderr.on("data", (chunk) => { output += chunk; });
    child.on("exit", (status) => resolve({ status, output }));
  });
}

async function makeManagedFixture(root) {
  const homeCandidate = path.join(root, "home");
  await mkdir(homeCandidate, { recursive: true, mode: 0o700 });
  const home = await realpath(homeCandidate);
  const persome = path.join(home, ".persome");
  const app = path.join(home, "Applications/Who Am I.app");
  await mkdir(path.join(app, "Contents"), { recursive: true, mode: 0o700 });
  await writeFile(path.join(app, "Contents/Info.plist"), managedInfoPlist, { mode: 0o600 });
  await mkdir(path.join(persome, "product-app/0.1.0"), { recursive: true, mode: 0o700 });
  await writeFile(path.join(persome, "product-app/0.1.0/product-version"), "0.1.0\n");
  await mkdir(path.join(home, "Library/Application Support/Who Am I"), {
    recursive: true,
    mode: 0o700,
  });
  await writeFile(
    path.join(home, "Library/Application Support/Who Am I/owner-profile.json"),
    "{}\n",
  );
  await mkdir(path.join(persome, "data"), { recursive: true, mode: 0o700 });
  await writeFile(path.join(persome, "data/personal-memory"), "preserve\n");
  return { home, persome, app };
}

test("native lifecycle source keeps install, update and destructive boundaries explicit", async () => {
  const [swift, launcher, appDelegate] = await Promise.all([
    readFile(path.join(appRoot, "macos/NativeLifecycle.swift"), "utf8"),
    readFile(path.join(appRoot, "macos/build-native-launcher.sh"), "utf8"),
    readFile(path.join(appRoot, "macos/WhoAmIApp.swift"), "utf8"),
  ]);

  assert.match(swift, /SELF-CONTAINED-SHA256SUMS/);
  assert.match(swift, /"--non-interactive"/);
  assert.match(swift, /requiresInteractiveStep/);
  assert.match(swift, /打开 Runtime 更新确认/);
  assert.match(swift, /candidate\.immutable/);
  assert.match(swift, /candidate\.assets\.count == 5/);
  assert.match(swift, /Set\(manifest\.keys\) == expectedEntries/);
  assert.match(swift, /release = nil[\s\S]*approvedRelease = nil/);
  assert.match(swift, /SHA256SUMS/);
  assert.match(swift, /hdiutil/);
  assert.match(swift, /prepare-permanent-delete/);
  assert.match(swift, /亲自输入 DELETE/);
  assert.doesNotMatch(appDelegate, /NSWorkspace\.shared\.open\(installerURL\)/);
  assert.match(appDelegate, /NativeInstallerView/);
  assert.match(appDelegate, /NativeMaintenanceView/);
  assert.match(launcher, /NativeLifecycle\.swift/);
  assert.match(launcher, /native-lifecycle-helper\.sh/);
});

test(
  "removing product code preserves Personal Model data and Card profile",
  { skip: process.platform !== "darwin" },
  async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "whoami-lifecycle-remove-"));
  try {
    const fixture = await makeManagedFixture(root);
    const result = await runHelper(
      fixture.home,
      "remove-product",
      fixture.persome,
      fixture.app,
    );
    assert.equal(result.status, 0, result.output);
    await assert.rejects(readFile(path.join(fixture.app, "Contents/Info.plist")));
    await assert.rejects(readFile(path.join(fixture.persome, "product-app/0.1.0/product-version")));
    assert.equal(
      await readFile(path.join(fixture.persome, "data/personal-memory"), "utf8"),
      "preserve\n",
    );
    assert.equal(
      await readFile(
        path.join(fixture.home, "Library/Application Support/Who Am I/owner-profile.json"),
        "utf8",
      ),
      "{}\n",
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
  },
);

test(
  "permanent deletion preparation refuses an independently managed Runtime",
  { skip: process.platform !== "darwin" },
  async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "whoami-lifecycle-external-"));
  try {
    const fixture = await makeManagedFixture(root);
    const result = await runHelper(
      fixture.home,
      "prepare-permanent-delete",
      fixture.persome,
      fixture.app,
    );
    assert.notEqual(result.status, 0);
    assert.match(result.output, /product-managed Runtime uninstaller is unavailable/);
    assert.equal(
      await readFile(path.join(fixture.persome, "data/personal-memory"), "utf8"),
      "preserve\n",
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
  },
);

test(
  "managed permanent deletion still requires the Runtime DELETE prompt",
  { skip: process.platform !== "darwin" },
  async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "whoami-lifecycle-delete-"));
  try {
    const fixture = await makeManagedFixture(root);
    const management = path.join(fixture.persome, "product-management");
    await mkdir(management, { recursive: true, mode: 0o700 });
    const uninstaller = path.join(management, "uninstall-runtime.sh");
    await writeFile(
      uninstaller,
      "#!/usr/bin/env bash\n[[ \"${1:-}\" == --check-ownership ]] && exit 0\nexit 91\n",
      { mode: 0o700 },
    );
    await chmod(uninstaller, 0o700);
    const result = await runHelper(
      fixture.home,
      "prepare-permanent-delete",
      fixture.persome,
      fixture.app,
    );
    assert.equal(result.status, 0, result.output);
    const commandPath = result.output.trim().split("\n").at(-1);
    const command = await readFile(commandPath, "utf8");
    assert.match(command, /--delete-data/);
    assert.doesNotMatch(command, /--yes/);
    assert.equal(
      await readFile(path.join(fixture.persome, "data/personal-memory"), "utf8"),
      "preserve\n",
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
  },
);
