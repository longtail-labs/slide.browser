import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "..");
const versionFile = join(root, "version.txt");

// --- Helpers ---
const run = (cmd: string, args: string[]) => {
	const r = spawnSync(cmd, args, { cwd: root, stdio: "pipe" });
	return r.stdout?.toString().trim() ?? "";
};

const fail = (msg: string): never => {
	console.error(`\n❌ ${msg}`);
	process.exit(1);
};

// --- Parse bump type from args ---
type Bump = "patch" | "minor" | "major";
const arg = process.argv[2] as string | undefined;
const bump: Bump = (arg === "minor" || arg === "major") ? arg : "patch";

// --- Bump version ---
const current = readFileSync(versionFile, "utf-8").trim();
const [major, minor, patch] = current.split(".").map(Number);
const newVersion =
	bump === "major" ? `${major + 1}.0.0` :
	bump === "minor" ? `${major}.${minor + 1}.0` :
	`${major}.${minor}.${patch + 1}`;

writeFileSync(versionFile, `${newVersion}\n`);
console.log(`🏷️  version: ${current} → ${newVersion}`);

// --- Check for staged files ---
let staged = run("git", ["diff", "--cached", "--name-only"])
	.split("\n")
	.filter(Boolean);

if (staged.length === 0) {
	console.log("⚠️  No staged files. Staging all tracked changes...");
	spawnSync("git", ["add", "-u"], { cwd: root, stdio: "inherit" });
}

// Always stage the version bump
spawnSync("git", ["add", "version.txt"], { cwd: root, stdio: "inherit" });

staged = run("git", ["diff", "--cached", "--name-only"])
	.split("\n")
	.filter(Boolean);

if (staged.length === 0) fail("Nothing to commit.");

// --- AI commit message via Claude CLI ---
const diff = run("git", ["diff", "--cached"]);
const fileList = staged.join("\n");

console.log("🤖 asking Claude for a commit message...");

const prompt = `You are writing a git commit message for Slide, a macOS browser/workspace app (SwiftUI + TCA).
Modified files:
${fileList}

Diff:
${diff}

Write a short conventional commit message. Rules:
- Single line: an emoji, then a conventional prefix (feat:, fix:, chore:, style:, refactor:), then brief summary, then (v${newVersion})
- No body, no bullet points — just the one-liner
- Output ONLY the commit message`;

const claudeResult = spawnSync("claude", ["-p", prompt], {
	cwd: root,
	stdio: "pipe",
	timeout: 30_000,
});

let commitMsg: string;

if (claudeResult.status !== 0 || !claudeResult.stdout?.toString().trim()) {
	console.warn("⚠️  Claude unavailable, using fallback");
	commitMsg = `🚀 chore: release v${newVersion}`;
} else {
	commitMsg = claudeResult.stdout.toString().trim();
}

console.log(`\n📝 ${commitMsg}\n`);

// --- Commit & push ---
const commitResult = spawnSync("git", ["commit", "-m", commitMsg], {
	cwd: root,
	stdio: "inherit",
});
if (commitResult.status !== 0) fail("git commit failed.");

console.log("\n⬆️  pushing to master...");
const pushResult = spawnSync("git", ["push", "origin", "master"], {
	cwd: root,
	stdio: "inherit",
});
if (pushResult.status !== 0) fail("git push failed.");

console.log(`\n✅ released v${newVersion} — CI will build and publish`);
