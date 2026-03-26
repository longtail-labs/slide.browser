import { spawnSync } from "node:child_process";
import { join } from "node:path";

const root = join(import.meta.dir, "..");

// --- Helpers ---
const run = (cmd: string, args: string[]) => {
	const r = spawnSync(cmd, args, { cwd: root, stdio: "pipe" });
	return r.stdout?.toString().trim() ?? "";
};

const fail = (msg: string): never => {
	console.error(`\n❌ ${msg}`);
	process.exit(1);
};

// --- Collect staged files ---
const staged = run("git", ["diff", "--cached", "--name-only"])
	.split("\n")
	.filter(Boolean);

if (staged.length === 0) {
	fail("No staged files to commit. Stage your changes with git add first.");
}

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
- Single line: an emoji, then a conventional prefix (feat:, fix:, chore:, style:, refactor:, docs:, test:, perf:), then a brief summary
- No body, no bullet points — just the one-liner
- No version number
- Output ONLY the commit message`;

const claudeResult = spawnSync("claude", ["-p", prompt], {
	cwd: root,
	stdio: "pipe",
	timeout: 30_000,
});

let commitMsg: string;

if (claudeResult.status !== 0 || !claudeResult.stdout?.toString().trim()) {
	console.warn("⚠️  Claude unavailable, using fallback");

	const classify = (file: string): string => {
		if (/\.(test|spec)\.[tj]sx?$/.test(file)) return "test";
		if (/^(README|CHANGELOG|docs\/)/i.test(file)) return "docs";
		if (/^(scripts\/|\.github\/|conveyor)/i.test(file)) return "chore";
		if (/\.(css|scss)$/.test(file)) return "style";
		return "feat";
	};

	const groups = new Map<string, string[]>();
	for (const f of staged) {
		const type = classify(f);
		if (!groups.has(type)) groups.set(type, []);
		groups.get(type)!.push(f);
	}

	const prefixOrder = ["feat", "fix", "style", "test", "docs", "chore"];
	const dominant = prefixOrder.find((p) => groups.has(p)) ?? "chore";

	const summarize = (files: string[]): string =>
		files
			.map((f) => f.split("/").pop()!.replace(/\.[^.]+$/, ""))
			.slice(0, 4)
			.join(", ") + (files.length > 4 ? ` +${files.length - 4} more` : "");

	commitMsg = `🚀 ${dominant}: ${summarize(staged)}`;
} else {
	commitMsg = claudeResult.stdout.toString().trim();
}

console.log(`\n📝 ${commitMsg}\n`);

// --- Commit ---
const commitResult = spawnSync("git", ["commit", "-m", commitMsg], {
	cwd: root,
	stdio: "inherit",
});
if (commitResult.status !== 0) fail("git commit failed.");

console.log("\n✅ committed!");
