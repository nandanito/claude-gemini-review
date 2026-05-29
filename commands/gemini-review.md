---
description: Review the current branch's PR diff with the Gemini CLI (read-only second opinion). Modes — adversarial, doctor; flag — --comment posts findings to the PR.
---

You are running a **second-opinion code review** using the Gemini CLI. This
gives an independent model a look at the change before merge — complementary
to `/codex:review`. Argument: `$ARGUMENTS`.

## Modes — parse `$ARGUMENTS` first

Tokenize `$ARGUMENTS` and route before doing anything else:

- First token is **`doctor`** → run the **Doctor** health check below and stop.
  Ignore all other arguments.
- A token is **`adversarial`** (or **`adv`**) → use the **Adversarial review
  prompt** instead of the standard one. Remove the token; the rest selects the
  target.
- **`--comment`** appears anywhere → after the review, **post the findings to
  the PR** (see *Posting to the PR*). Remove the token; the rest selects the
  target.
- Whatever remains selects the **target** (see Step 2).

## Core constraint

- This command is **review-only**. Do not fix issues, apply patches, or edit
  files. The single write action permitted is posting a PR comment, and only
  when `--comment` was explicitly requested.
- Return Gemini's findings **verbatim** under a short header. Do not paraphrase,
  re-grade, or silently drop findings. You may add a one-line note at the end
  if a finding is clearly wrong, but never edit Gemini's text.

## Doctor — `/gemini-review doctor`

A read-only health check. The point is to catch the confusing failure modes
*before* a real review. Run these and print a ✓/✗ checklist, with a one-line
remediation for each ✗; end with an overall **READY** / **NOT READY**.

1. **Installed?** `command -v gemini` and `gemini --version`. If missing:
   `npm i -g @google/gemini-cli`.
2. **In a git repo?** `git rev-parse --is-inside-work-tree`.
3. **Auth + trust + plan-mode actually work** (the end-to-end check static
   preflight can't do) — one tiny live call:
   ```bash
   printf 'Reply with exactly the token READY and nothing else.\n' \
     | gemini --skip-trust --approval-mode plan -o text -p 'Follow the stdin instruction.'
   ```
   - exit 0 and output contains `READY` → ✓ authenticated, trust gate cleared,
     plan mode held.
   - auth error → run `gemini` once interactively to sign in, or set
     `GEMINI_API_KEY`.
   - a "not trusted" / "approval mode overridden" warning → confirm the call
     includes `--skip-trust` (this command always passes it).
4. **`gh` for PR features** (optional — only needed for PR-number targets and
   `--comment`): `command -v gh` and `gh auth status`. Report as optional.

## Step 1 — Preflight (review modes)

- Confirm the `gemini` binary is on PATH (`command -v gemini`). If not, stop and
  tell the user to install it (`npm i -g @google/gemini-cli`) and authenticate
  (run `gemini` once interactively, or set `GEMINI_API_KEY`). Suggest
  `/gemini-review doctor` to diagnose. Do not attempt the review without it.
- You must be inside a git repository. If not, stop and say so.

## Step 2 — Determine the review target from the remaining args

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
- **`wip` or `--working`** → include uncommitted work: `git diff HEAD`
  (unstaged + staged vs HEAD). Use this when reviewing before committing.
- Anything else → treat as **extra focus text** layered on the default
  branch-vs-base diff (append it to the chosen prompt's focus line).

## Step 3 — Gather the diff

- Produce the unified diff for the chosen target and a `--stat` summary.
- If the diff is **empty**, report "nothing to review" and stop (do not invoke
  Gemini).
- Write the diff to a temp file (e.g. `mktemp`) so large diffs and special
  characters survive cleanly rather than going through shell quoting.

## Step 4 — Run Gemini (read-only)

Invoke Gemini in headless, **read-only plan mode**, feeding the diff on stdin
and the chosen review prompt via `-p`:

```bash
gemini --skip-trust --approval-mode plan -o text \
  -p "$REVIEW_PROMPT" < "$DIFF_FILE"
```

Why these flags:
- `--skip-trust` — clears the headless trusted-folder gate for this one session
  (Gemini refuses non-interactive runs in untrusted dirs otherwise).
- `--approval-mode plan` — **read-only**. Gemini may read repo files for context
  but cannot edit, write, or run mutating tools. This is the safety boundary;
  keep it.
- `-o text` — clean response text to relay. (Use `-o json` and read `.response`
  if you need to script around it.)
- The diff arrives on stdin; `-p` is appended after it.

Gemini headless is **slow** — budget on the order of a second per diff line
(a ~100-line diff takes ~80s; several hundred lines can exceed a few minutes).
Run the command in the background and wait rather than capping it short. For
very large changes, review the highest-risk paths first
(`/gemini-review <ref> -- <path>`) or split the review, and tell the user you
did so — don't silently truncate the diff.

Pick the prompt by mode:

### Standard review prompt

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

### Adversarial review prompt (`adversarial` / `adv`)

```
You are a hostile, adversarial code reviewer. A unified git diff is provided on
stdin. Assume the change is guilty until proven innocent — your goal is to MAKE
IT FAIL, not to praise it.

If present, read AGENTS.md, GEMINI.md, CLAUDE.md, and README for the project's
contracts (read-only; do not edit). Then attack the diff along every axis:
- adversarial / malformed / empty / boundary / enormous inputs
- concurrency: races, deadlocks, TOCTOU, shared-state corruption, ordering
- error & failure paths: partial failure, missing rollback, swallowed errors,
  leaked resources, unhandled rejections
- security: injection, path traversal, SSRF, secret leakage, unsafe
  deserialization, missing authz, untrusted input reaching a dangerous sink
- arithmetic & types: overflow, truncation, off-by-one, null/undefined,
  unchecked casts
- API/contract violations between caller and callee, and broken invariants

For EVERY issue, give a CONCRETE failing scenario — the specific input,
sequence, or condition that triggers it — not a vague worry. Verify each claim
against the code in the diff; if you cannot construct a trigger, do not report
it. Do not pad with style nits.

For every finding provide:
- Severity: CRITICAL / HIGH / MEDIUM / LOW
- File path and line number(s)
- The failing scenario and why it breaks
- A concrete fix

Sort by severity, highest first. If a severity bucket is empty, say so
explicitly. End with a one-line verdict (safe to merge / fix-before-merge /
needs discussion). This is review-only — propose fixes, do not make them.
```

If the user supplied extra focus text (Step 2, last case), append a line to the
chosen prompt: `Pay particular attention to: <focus>.`

## Step 5 — Handle the result

- Gemini exit codes: `0` success, `1` general/API error, `42` input error,
  `53` turn-limit exceeded.
- On success, print a header — `# Gemini Review — <target>` (or
  `# Gemini Adversarial Review — <target>` in adversarial mode) — then Gemini's
  output verbatim.
- On non-zero exit with no useful output, report the failure and likely cause:
  - auth → run `gemini` once interactively, or set `GEMINI_API_KEY`
    (`/gemini-review doctor` diagnoses this).
  - `53` → the diff was large; re-run on a narrower path
    (`/gemini-review <ref> -- path/`) or split the review.
- Do not fix any issue Gemini raises. Surfacing them is the job; the user
  decides what to act on.

## Posting to the PR (`--comment`)

Only when `--comment` was explicitly given. This is the one write action the
command may take; it still **never edits code**.

1. Resolve the PR number: if the target was a PR number, use it; otherwise find
   the PR for the current branch (`gh pr view --json number,url`). If there is
   no open PR, do **not** post — show the review and say no PR was found.
2. Post the review **verbatim**, prefixed with a provenance header, via:
   ```bash
   gh pr comment <PR#> --body-file <file>
   ```
   Header to prepend to the comment body:
   `🔭 **Gemini review** — read-only second opinion via the Gemini CLI (automated, advisory).`
3. Report the resulting comment URL back to the user.
4. If `gh` is missing or unauthenticated, skip posting, show the review inline,
   and tell the user (`/gemini-review doctor` checks `gh`).
