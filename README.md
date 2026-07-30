# claude-gemini-review

A [Claude Code](https://claude.com/claude-code) slash command that runs the
**Antigravity CLI** (`agy`) as a read-only, second-opinion code reviewer over
your current change — handy as a final pass before merging a PR, and a nice
complement to `/codex:review` (a different model looking at the same diff).

> **Migrated from the Gemini CLI.** Google replaced the Gemini CLI with the
> [Antigravity CLI](https://antigravity.google) (`agy`) and retired the legacy
> tool in June 2026. This command now drives `agy`. The slash command is still
> `/gemini-review` — the name is unchanged so existing installs keep working,
> and `agy` still runs Gemini models. See [Migrating](#migrating-from-the-gemini-cli).

![/gemini-review adversarial running a read-only, hostile review of a PR diff](demo/gemini-review.gif)

<sub>Shown in <strong>adversarial mode</strong> (<code>/gemini-review adversarial 42</code>) —
each finding comes with a concrete failing scenario. Output is representative;
see [`demo/`](demo/). The recording predates the <code>agy</code> migration, so
it shows the older, slower Gemini CLI run; the review format is unchanged.</sub>

```
/gemini-review            # review this branch's PR diff vs its base
/gemini-review 42         # review GitHub PR #42
/gemini-review develop    # diff against a ref/branch
/gemini-review wip        # include uncommitted work
/gemini-review "focus on the retry logic"   # add an extra focus area
```

Findings are returned **verbatim** — severity-tagged (CRITICAL/HIGH/MEDIUM/LOW),
with file:line, the problem, and a recommended fix, ending in a one-line verdict.

### Modes & flags

```
/gemini-review adversarial      # hostile pass — assume it's broken, try to make it fail
/gemini-review adversarial 42   # …on a specific PR
/gemini-review 42 --comment     # post the findings to PR #42 as a comment (needs gh)
/gemini-review doctor           # check agy, auth, and headless mode are working
```

- **`adversarial`** swaps in a skeptical prompt that hunts for races, bad
  inputs, error paths, overflow, and security holes — and demands a concrete
  failing scenario for each. Same speed as a normal review (one pass).
- **`--comment`** posts the review verbatim to the pull request (the only write
  the command makes — it still never edits code). Resolves the PR from the
  argument or the current branch.
- **`doctor`** runs a tiny live call to confirm auth and headless print mode
  work end to end — the failure modes static checks miss.

## How it works

The command builds the diff, embeds it in the prompt, and runs `agy` headlessly:

```bash
git diff --text <base>...HEAD | tr -d '\000' > "$DIFF_FILE"
# $REVIEW_PROMPT + the diff, inline, written to $PROMPT_FILE
agy -p "$(cat "$PROMPT_FILE")" --mode plan --output-format json --print-timeout 10m
```

- **The diff goes inline in the prompt, not on stdin.** `agy` ignores stdin
  entirely — the old `gemini -p "$PROMPT" < "$DIFF_FILE"` form would silently
  review *nothing*. Everything the model sees is in the prompt.
- **Nothing is read from disk.** Because the whole diff is in the prompt, the
  model never needs to open a file. That's what makes the run both safe and
  fast, and it removes the file-read loop that used to hang the Gemini version
  on multi-file diffs.
- **`git diff --text | tr -d '\000'`** forces a textual diff and strips NUL
  bytes, so a file git would otherwise call "binary" still gets reviewed.
- **`--print-timeout`** is a built-in watchdog, replacing the hand-rolled
  `sleep`/`kill` wrapper the Gemini version needed.

The command never edits your code. It surfaces findings; you decide what to act
on.

### The safety boundary (it moved — worth knowing)

With the old Gemini CLI, `--approval-mode plan` was the read-only guarantee.
**That is no longer true.** In `agy`, `--mode plan` is a behavioral hint, not a
sandbox — given `--dangerously-skip-permissions`, plan mode will happily create
and overwrite files.

The actual boundary is the permission system: **in headless `--print` mode any
tool needing approval (`read_file`, `write_file`, shell) is auto-denied**,
because there is nothing to prompt. So the rule is simply:

> **Never add `--dangerously-skip-permissions` to this command.**

That single omission is what keeps the run read-only. `--mode plan` is still
passed as cheap defense-in-depth.

## Prerequisites

- [**Claude Code**](https://claude.com/claude-code).
- The **Antigravity CLI** (`agy`), installed and authenticated:
  ```bash
  curl -fsSL https://antigravity.google/install.sh | bash   # macOS / Linux
  # Windows: winget install Google.AntigravityCLI
  agy            # run once interactively to sign in
  ```
  `agy update` upgrades in place; `agy --version` reports the build.
- **git** (always) and the **GitHub CLI** (`gh`) only for the PR-number form
  (`/gemini-review 42`) and `--comment`.

## Install

The command is a single Markdown file. Put it wherever Claude Code looks for
commands:

**Personal (available in every project):**
```bash
mkdir -p ~/.claude/commands
curl -fsSL https://raw.githubusercontent.com/nandanito/claude-gemini-review/main/commands/gemini-review.md \
  -o ~/.claude/commands/gemini-review.md
```

**Project-scoped (committed with one repo, shared with collaborators):**
```bash
mkdir -p .claude/commands
cp commands/gemini-review.md .claude/commands/
```

Or clone and symlink so you pick up updates with `git pull`:
```bash
git clone https://github.com/nandanito/claude-gemini-review.git
ln -s "$PWD/claude-gemini-review/commands/gemini-review.md" ~/.claude/commands/gemini-review.md
```

Then invoke `/gemini-review` from inside any git repository.

## Migrating from the Gemini CLI

`agy` detects an existing Gemini setup on first run and offers to carry over
your settings. To do it explicitly:

```bash
agy plugin import gemini
```

Two things to know if you had the old tool configured:

- **Config moved** to `~/.antigravity/`; `agy` keeps its working state under
  `~/.gemini/antigravity-cli/`.
- **`GEMINI.md` → `AGENTS.md`.** Legacy `GEMINI.md` files are still recognized,
  but the current convention is `AGENTS.md` (and `.agents/skills/`).

You do **not** need to reinstall this slash command — only the CLI underneath it
changed.

## A note on speed

`agy` is substantially faster than the old Gemini CLI. A ~10 KB, ~250-line diff
reviews in roughly **10–15 seconds**, where the Gemini version budgeted about a
second per line of diff. The command just runs it and waits — no backgrounding,
no polling.

To tune further:
- **Faster model for large diffs:** `--model gemini-3.6-flash-medium`. Run
  `agy models` for the current list (`gemini-3.1-pro-high` is the
  high-reasoning end).
- **Reasoning effort:** `--effort low|medium|high` — `high` for a small,
  high-stakes change, `low` for a large mechanical one.
- **Narrow the review:** `/gemini-review <ref> -- <path>` to focus on source and
  skip docs, lockfiles, and generated code.

## Troubleshooting

- **Empty review, but the command "succeeded"** → `agy` exits **`0` even on
  failure**, and its JSON reports `"status":"SUCCESS"` even when it produced
  nothing. The only reliable signal is a **non-empty `.response`**, which the
  command checks; the real diagnostic goes to **stderr**.
- **stderr says a tool was auto-denied** (`read_file` / `write_file`) → the
  model tried to touch the filesystem. That's the safety boundary doing its job.
  Fix it by reinforcing the "judge from the diff alone" instruction — **not** by
  adding `--dangerously-skip-permissions`.
- **"argument list too long"** → the diff is passed through `argv`, which is
  capped by `ARG_MAX` (~1 MB including the environment). The command guards at
  256 KB and asks you to narrow with a pathspec or split the review rather than
  silently truncating.
- **"nothing to review" / a path filter matched no changes** → the command
  hard-checks the diff is non-empty before invoking `agy` and aborts if not.
- **A file is missing from the review** → it likely contains a NUL/binary byte,
  so git dropped it as "binary." The command uses `git diff --text` and strips
  NUL bytes so it's reviewed anyway.
- **The review doesn't follow our conventions** → the model **cannot** read
  `AGENTS.md` / `CLAUDE.md` / `README` (those reads are denied). Pass what
  matters as focus text: `/gemini-review "we never throw in handlers"`.
- **Auth errors** → run `/gemini-review doctor`, which makes one tiny live call
  to check auth and headless mode end to end.

## License

[MIT](./LICENSE)
