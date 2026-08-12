import { execFile } from "node:child_process";
import path from "node:path";
import { promisify } from "node:util";

const run = promisify(execFile);

export default async function afterPack(context) {
  if (context.electronPlatformName !== "darwin") return;
  if (process.env.CSC_LINK || process.env.CSC_NAME) return;
  if (/mac-universal-(?:x64|arm64)-temp$/.test(context.appOutDir)) return;

  const appPath = path.join(
    context.appOutDir,
    `${context.packager.appInfo.productFilename}.app`,
  );
  await run("/usr/bin/codesign", [
    "--deep",
    "--force",
    "--sign",
    "-",
    "--timestamp=none",
    appPath,
  ]);
}
