// Normalizes public-release artifacts into ASCII-safe filenames for GitHub Actions.
import { copyFile, mkdir, readdir, rm } from "node:fs/promises";
import path from "node:path";

const [platform, inputDirArg, outputDirArg, releaseVersionArg = ""] = process.argv.slice(2);
const SUPPORTED_PLATFORMS = new Set(["windows", "android", "macos", "harmony"]);

function usage() {
  console.error("Usage: node scripts/prepare-public-build-artifacts.mjs <windows|android|macos|harmony> <inputDir> <outputDir> [releaseVersion]");
}

async function listFiles(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...await listFiles(fullPath));
      continue;
    }
    if (entry.isFile()) {
      files.push(fullPath);
    }
  }
  return files;
}

function normalizeReleaseToken(value) {
  const normalized = String(value ?? "").trim();
  if (!normalized) {
    return "unknown";
  }

  return normalized
    .replace(/[^0-9A-Za-z._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "") || "unknown";
}

function matchPlatformArtifact(targetPlatform, filePath) {
  const extension = path.extname(filePath).toLowerCase();
  if (targetPlatform === "windows") {
    return extension === ".exe";
  }
  if (targetPlatform === "android") {
    return extension === ".apk";
  }
  if (targetPlatform === "macos") {
    return extension === ".dmg";
  }
  return extension === ".hap";
}

function detectAndroidLabel(filePath) {
  const normalized = filePath.replaceAll("\\", "/").toLowerCase();
  if (normalized.includes("universal")) {
    return "android-universal";
  }
  if (normalized.includes("arm64") || normalized.includes("aarch64")) {
    return "android-arm64";
  }
  if (normalized.includes("armv7") || normalized.includes("armeabi-v7a")) {
    return "android-armv7";
  }
  if (normalized.includes("x86_64")) {
    return "android-x86_64";
  }
  if (normalized.includes("/x86/") || normalized.includes("i686")) {
    return "android-x86";
  }
  return "android";
}

function buildLabel(targetPlatform, filePath) {
  if (targetPlatform === "windows") {
    return "windows";
  }
  if (targetPlatform === "android") {
    return detectAndroidLabel(filePath);
  }
  if (targetPlatform === "macos") {
    return "macos";
  }
  return "harmony";
}

async function main() {
  if (!SUPPORTED_PLATFORMS.has(platform) || !inputDirArg || !outputDirArg) {
    usage();
    process.exit(1);
  }

  const inputDir = path.resolve(inputDirArg);
  const outputDir = path.resolve(outputDirArg);
  const releaseToken = normalizeReleaseToken(releaseVersionArg);

  const allFiles = await listFiles(inputDir);
  const matchedFiles = allFiles
    .filter((filePath) => matchPlatformArtifact(platform, filePath))
    .sort((left, right) => left.localeCompare(right));

  if (!matchedFiles.length) {
    throw new Error(`No ${platform} artifacts were found under ${inputDir}`);
  }

  await rm(outputDir, { force: true, recursive: true });
  await mkdir(outputDir, { recursive: true });

  const labelCounts = new Map();
  for (const sourcePath of matchedFiles) {
    const label = buildLabel(platform, sourcePath);
    const nextCount = (labelCounts.get(label) ?? 0) + 1;
    labelCounts.set(label, nextCount);

    const duplicateSuffix = nextCount === 1 ? "" : `-${nextCount}`;
    const extension = path.extname(sourcePath).toLowerCase();
    const fileName = `MgRead-${label}-${releaseToken}${duplicateSuffix}${extension}`;
    const destinationPath = path.join(outputDir, fileName);

    await copyFile(sourcePath, destinationPath);
    console.log(`[prepare-public-build-artifacts] ${sourcePath} -> ${destinationPath}`);
  }
}

main().catch((error) => {
  console.error(`[prepare-public-build-artifacts] ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});
