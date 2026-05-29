---
description: Review the current branch's PR diff with the Gemini CLI (read-only second opinion)
---

You are running a **second-opinion code review** using the Gemini CLI. This
gives an independent model a look at the change before merge — complementary
to `/codex:review`. Argument: `$ARGUMENTS`.

## Core constraint

- This command is **review-only**. Do not fix issues, apply patches, edit
  files, or say you are about to make changes.
- Your job is to run Gemini against the diff and return Gemini's findings to
  the user **verbatim** under a short header. Do not paraphrase, re-grade, or
  silently drop findings. You may add a one-line note at the end if a finding
  is clearly wrong, but never edit Gemini's text.

## Step 1 — Preflight

- Confirm the `gemini` binary is on PATH (`command -v gemini`). If it is not,
  stop and tell the user to install the Gemini CLI (`npm i -g @google/gemini-cli`)
  and authenticate (run `gemini` once interactively to sign in, or set
  `GEMINI_API_KEY`). Do not attempt the review without it.
- You must be inside a git repository. If not, stop and say so.

## Step 2 — Determine the review target from `$ARGUMENTS`

Interpret the argument as follows:

- **Empty** → review this branch's PR diff against its base. Detect the base:
  try the remote default branch
  (`git symbolic-ref --quiet refs/remotes/origin/HEAD` → strip to the branch
  name); if that fails, use `main`, then `master`. The diff is
  `git diff <base>...HEAD` (three-dot: merge-base to HEAD = exactly this
  branch's changes).
- **A bare integer** (e.g. `42`) → a GitHub PR. Use `gh pr diff 42` for the
  diff and `gh pr view 42` for the title/body so Gemini has the intent.
- **A git ref / branch name** (e.g. `develop`) → diff against it:
  `git diff <ref>...HEAD`.
- **`wip` or `--working`** → include uncommitted work: combine
  `git diff HEAD` (unstaged + staged vs HEAD). Use this when reviewing before
  committing.
- Anything else → treat as **extra focus text** layered on the default
  branch-vs-base diff (pass it into the review prompt's focus line).

## Step 3 — Gather the diff

- Produce the unified diff for the chosen target and a `--stat` summary.
- If the diff is **empty**, report "nothing to review" and stop (do not invoke
  Gemini).
- Write the diff to a temp file (e.g. `mktemp`) so large diffs and special
  characters survive cleanly rather than going through shell quoting.

## Step 4 — Run Gemini (read-only)

Invoke Gemini in headless, **read-only plan mode**, feeding the diff on stdin
and the review instructions via `-p`. Recommended command:

```bash
gemini --skip-trust --approval-mode plan -o text \
  -p "$REVIEW_PROMPT" < "$DIFF_FILE"
```

Why these flags:
- `--skip-trust` — clears the headless trusted-folder gate for this one
  session (Gemini refuses non-interactive runs in untrusted dirs otherwise).
- `--approval-mode plan` — **read-only**. Gemini may read repo files for
  context but cannot edit, write, or run mutating tools. This is the safety
  boundary; keep it.
- `-o text` — clean response text to relay. (Use `-o json` and read
  `.response` if you need to script around it.)
- The diff arrives on stdin; `-p` is appended after it, so Gemini sees the
  diff first, then the instructions.

Gemini headless is **slow** — budget on the order of a second per diff line
(a ~100-line diff takes ~80s; several hundred lines can exceed a few
minutes). Run the command in the background and wait for it rather than
capping it short. For very large changes, review the highest-risk paths
first (`/gemini-review <ref> -- <path>`) or split the review, and tell the
user you did so — don't silently truncate the diff.

Use this exact `$REVIEW_PROMPT` (the diff is on stdin):

```
You are a meticulous senior code reviewer. A unified git diff is provided on
stdin. Review ONLY that change.

First, if present, read the repo's conventions from AGENTS.md, GEMINI.md,
CLAUDE.md, and README before judging — match the project's existing patterns,
runtime, and norms. You are in read-only mode; reading is allowed, editing is
not.

Focus on real defects, in priority order:
- correctness bugs and logic errors
- security issues (injection, authz, secrets, unsafe input handling)
- API / contract mismatches between caller and callee
- data-integrity and concurrency problems
- error handling and resource leaks
- missing or wrong tests for the changed behavior
Do NOT report pure style/formatting nits unless they cause a real bug. Verify
each claim against the actual code in the diff before reporting it; do not
speculate. If you are unsure, say so and lower the severity.

For every finding provide:
- Severity: CRITICAL / HIGH / MEDIUM / LOW
- File path and line number(s)
- What is wrong and why it matters
- A concrete recommended fix

Sort findings by severity, highest first. If a severity bucket is empty, say
so explicitly (e.g. "CRITICAL: none"). End with a one-line overall verdict
(safe to merge / fix-before-merge / needs discussion). Be concise and
specific. This is review-only — do not propose to make the edits yourself.
```

If the user supplied extra focus text (Step 2, last case), append a line to
the prompt: `Pay particular attention to: <focus>.`

## Step 5 — Handle the result

- Gemini exit codes: `0` success, `1` general/API error, `42` input error,
  `53` turn-limit exceeded.
- On success, print a header like `# Gemini Review — <target>` then Gemini's
  output verbatim.
- On non-zero exit with no useful output, report the failure and the likely
  cause:
  - auth → run `gemini` once interactively to sign in, or set `GEMINI_API_KEY`
  - `53` → the diff was large; suggest re-running on a narrower path
    (`/gemini-review <ref> -- path/`) or splitting the review.
- Do not fix any issue Gemini raises. Surfacing them is the whole job; the
  user decides what to act on.
