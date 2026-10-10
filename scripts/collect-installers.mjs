import { copyFileSync, existsSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const [label, outDir] = process.argv.slice(2);

const stableNames = {
  macOS: [[".dmg", "TheBoss-macOS.dmg"]],
  Windows: [["-setup.exe", "TheBoss-Windows-setup.exe"]],
  Linux: [
    [".AppImage", "TheBoss-Linux.AppImage"],
    [".deb", "TheBoss-Linux.deb"],
  ],
};

function walk(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? walk(path) : [path];
  });
}

const bundles = walk("target").filter((path) => path.includes(`${join("release", "bundle")}`));
mkdirSync(outDir, { recursive: true });

for (const [suffix, stableName] of stableNames[label] ?? []) {
  const match = bundles.find((path) => path.endsWith(suffix));
  if (!match) {
    console.error(`No ${suffix} bundle found for ${label}`);
    process.exit(1);
  }
  copyFileSync(match, join(outDir, stableName));
  console.log(`${match} -> ${stableName}`);
}
