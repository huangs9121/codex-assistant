import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";

const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const directory = path.dirname(fileURLToPath(import.meta.url));
const source = pathToFileURL(path.join(directory, "poster-candidates.html")).href;

for (const key of ["b"]) {
  const profile = mkdtempSync(path.join(tmpdir(), "codex-poster-"));
  try {
    execFileSync(chrome, [
      "--headless=new",
      "--disable-gpu",
      "--disable-background-networking",
      "--hide-scrollbars",
      `--user-data-dir=${profile}`,
      "--window-size=1080,1440",
      "--force-device-scale-factor=1",
      `--screenshot=${path.join(directory, `poster-${key}.png`)}`,
      `${source}?poster=${key}`,
    ], { stdio: "ignore" });
  } finally {
    rmSync(profile, { recursive: true, force: true });
  }
}
