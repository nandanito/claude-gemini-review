# claude-gemini-review

A [Claude Code](https://claude.com/claude-code) slash command that runs the
**Gemini CLI** as a read-only, second-opinion code reviewer over your current
change — handy as a final pass before merging a PR, and a nice complement to
`/codex:review` (a different model looking at the same diff).

```
/gemini-review            # review this branch's PR diff vs its base
/gemini-review 42         # review GitHub PR #42
/gemini-review develop    # diff against a ref/branch
/gemini-review wip        # include uncommitted work
/gemini-review "focus on the retry logic"   # add an extra focus area
```

Gemini's findings are returned **verbatim** — severity-tagged
(CRITICAL/HIGH/MEDIUM/LOW), with file:line, the problem, and a recommended fix,
ending in a one-line verdict.

## How it works

The command drives Gemini headlessly and read-only:

```bash
git diff <base>...HEAD > "$DIFF_FILE"
gemini --skip-trust --approval-mode plan -o text -p "$REVIEW_PROMPT" < "$DIFF_FILE"
```

- **`--approval-mode plan`** keeps Gemini **read-only** — it may read files in
  the repo for context, but cannot edit, write, or run mutating tools. This is
  the safety boundary, and it's why the command is safe to run unattended.
- **`--skip-trust`** clears Gemini's headless "trusted folder" gate for that one
  session. Without it, Gemini refuses to run non-interactively in an untrusted
  directory *and* silently downgrades plan mode — so the flag is required, and
  plan mode still keeps the run read-only.
- The diff goes in on **stdin**; the review instructions go in via **`-p`**.

The command itself never edits your code. It surfaces findings; you decide what
to act on.

## Prerequisites

- [**Claude Code**](https://claude.com/claude-code).
- The **Gemini CLI** (`gemini`), installed and authenticated:
  ```bash
  npm i -g @google/gemini-cli
  gemini            # run once interactively to sign in (OAuth)
  #   …or set GEMINI_API_KEY in your environment
  ```
- **git** (always) and the **GitHub CLI** (`gh`) only for the PR-number form
  (`/gemini-review 42`).

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

## A note on speed

Gemini's headless review is **not instant** — budget roughly a second per line
of diff (a ~100-line diff takes ~80s; several hundred lines can run a few
minutes). The command runs Gemini in the background and waits. For very large
changes, review the highest-risk paths first or split the review rather than
truncating the diff.

## License

[MIT](./LICENSE)
