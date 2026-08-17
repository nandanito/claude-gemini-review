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
/gemini-review develop -- src/   # restrict to a path
```

Findings are returned **verbatim** — severity-tagged (CRITICAL/HIGH/MEDIUM/LOW),
with file:line, the problem, and a recommended fix, ending in a one-line verdict.

### Modes & flags

```
/gemini-review adversarial      # hostile pass — assume it's broken, try to make it fail
/gemini-review adversarial 42   # …on a specific PR
/gemini-review --focus "..."    # point the review at specific concerns (see below)
/gemini-review --save review.md # keep the review as a file
/gemini-review 42 --comment     # post the findings to PR #42 as a comment (needs gh)
/gemini-review doctor           # check agy, auth, jq, and headless mode are working
```

- **`adversarial`** swaps in a skeptical prompt that hunts for races, bad
  inputs, error paths, overflow, and security holes — and demands a concrete
  failing scenario for each. Same speed as a normal review (one pass).
- **`--focus`** is the highest-value flag here. [See below](#focus-text-the-highest-value-lever).
- **`--save <path>`** writes the review verbatim to a file with a provenance
  header (target, model, effort, mode). Useful when there's no PR to comment on
  and you want the review to outlive your scrollback.
- **`--comment`** posts the review verbatim to the pull request, with the same
  provenance block — the posted copy needs it most, since its readers weren't
  present for the run and can't recover the model afterward. Resolves the PR
  from the argument or the current branch.
- **`doctor`** runs a tiny live call to confirm auth and headless print mode
  work end to end — the failure modes static checks miss.

`--save` and `--comment` are the only writes the command makes, both opt-in and
both containing nothing but the review. It never edits code.

## Focus text: the highest-value lever

Focus text is the difference between a decent review and a targeted one, and it
composes with every target:

```
/gemini-review 42 --focus "the nonce derivation and the hybrid rejection argument"
/gemini-review develop --focus "..."
/gemini-review wip --focus "..."
```

**Focus text is allowed to be long and structured.** A multi-paragraph block
with numbered claims and specific pointers is the intended use, not an abuse of
the argument. Slash-command arguments are passed to the command **literally** —
there is no shell involved, so you don't quote-escape or use a heredoc. Just
type or paste the block straight after `--focus`, newlines and all:

```
/gemini-review --focus "Check these specific claims, by name, and say so
explicitly if each is sound:

1. ADR-002 rejects the hybrid approach on the grounds that it doubles write
   amplification. Verify that reasoning actually follows from the benchmark
   table above it — I think the table measures a different workload.
2. The 'homomorphism' claim in findings.md section 4 asserts f(a·b) = f(a)·f(b)
   for the encoding. Check the algebra, not the prose around it.
3. Citations: the same source line is cited in five places. Confirm they agree.

Beyond these, do your normal sweep and report anything else you find."
```

(In the terminal, `⌥↵` / `Esc↵` inserts a newline without submitting; pasting a
multi-line block works directly.)

**Keep the quotes, and put other flags first.** Quoted focus text is lifted out
of the arguments before anything else is matched, so prose containing words like
`adversarial`, `main`, or `wip` stays prose instead of quietly switching the mode
or retargeting the review. Unquoted focus text runs to the end of the input, so
the target and any other flags go *before* it:

```
/gemini-review 42 adversarial --save review.md --focus "…long block…"
```

**Focus adds priorities; it does not narrow scope.** This matters more than it
sounds. Focused and unfocused runs find *different* defects and neither is a
superset of the other — in one measured comparison the focused run caught two
substantive reasoning errors the unfocused run never reached, while the
unfocused run opened with a genuine CRITICAL and caught a cross-document
citation inconsistency that the focused run missed. The prompt therefore
instructs the model to address every focus item by name **and** complete the
standard sweep, so you get both sets rather than trading one for the other.

### It works on prose, not just code

The prompts are written in code-review vocabulary (TOCTOU, SSRF, unchecked
casts), which looks like it would return a false "CRITICAL: none" on a
documentation diff. Tested against a 95 KB prose diff — research findings and
ADRs — it does not: the model treats "code reviewer" as a *stance*, not a
content filter. It reviewed the reasoning, opened with a genuine CRITICAL, and
returned fix-before-merge. Reviewing design docs, ADRs, and specs is a supported
use; reach for `--focus` to point it at the specific claims you want checked.

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
- **`jq`** (preferred) or **`python3`** — used to check whether the review
  actually produced output. Not cosmetic: without a JSON parser that check
  degrades and an empty review can read as a clean one.
  `brew install jq` / `apt install jq`. (`jq` is preferred because `.response
  // ""` coalesces a null response for free; the `python3` fallback must use
  `.get("response") or ""` — `.get("response", "")` returns `None` on an
  explicit null and would report a failed run as a review reading `None`.
  `doctor` probes for exactly this.)
- **git** (always) and the **GitHub CLI** (`gh`) only for the PR-number form
  (`/gemini-review 42`) and `--comment`.

`/gemini-review doctor` verifies all of these, including `jq`.

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

`agy` is substantially faster than the old Gemini CLI, and — more usefully — it
**scales sub-linearly**:

| prompt | time | output |
|---|---|---|
| ~10 KB (~250 lines) | ~12–16 s | ~2 KB |
| ~98 KB | ~46 s | ~15 KB (78 K in, 10 K thinking, 15 K out) |

**10× the input costs about 3× the time.** So don't pre-emptively split a large
diff — one 95 KB review finishing in under a minute usually beats three narrow
ones, and narrowing risks missing problems that span files. Run the whole thing;
narrow only if it actually drags. The command just runs it and waits — no
backgrounding, no polling.

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
  matters via [focus text](#focus-text-the-highest-value-lever):
  `/gemini-review --focus "we never throw in handlers"`.
- **Auth errors** → run `/gemini-review doctor`, which makes one tiny live call
  to check auth and headless mode end to end.

## License

[MIT](./LICENSE)
