---
description: Review the current branch's PR diff with the Antigravity CLI (agy) — read-only second opinion. Modes — adversarial, doctor; flags — --focus targets the review, --save writes it to a file, --comment posts it to the PR.
---

You are running a **second-opinion code review** using the **Antigravity CLI
(`agy`)** — Google's successor to the Gemini CLI, which was retired in June
2026. This gives an independent model a look at the change before merge —
complementary to `/codex:review`. Argument: `$ARGUMENTS`.

## Modes — parse `$ARGUMENTS` first

Tokenize `$ARGUMENTS` and consume in **exactly this order**. Each step removes
what it claims; later steps only ever see the remainder.

**Rule 0 — quoting makes something content, never syntax.** This applies to
**every quoted span**, not only one following `--focus`. Lift all quoted spans
out *first*, set them aside, and run every step below on what is left. Inside a
quoted span nothing is ever matched as a flag, a mode token, a separator, or a
target — including the bare `--` split and the `adversarial` match.

This is what lets focus prose read naturally in **both** supported forms:

| input | why Rule 0 matters |
|---|---|
| `--focus "the retry logic -- especially backoff"` | the ` -- ` stays prose, not a pathspec split |
| `"check the adversarial path -- especially backoff"` | focus-only form: **same protection**, still a standard review of the branch diff |

The second row is the one that is easy to get wrong. The focus-only form has no
`--focus` marker in front of it, so a rule scoped to "spans after `--focus`"
would leave it exposed — `adversarial` would flip the mode and ` -- ` would
become a pathspec, producing a confident review of the wrong thing.

A flag that takes an argument (`--save`, `--focus`) may still **consume** a
quoted span as its value; that is the flag claiming it, not the span being
interpreted. And a quoted span is never a **target**: `/gemini-review "develop"`
is focus text on the default diff, while unquoted `/gemini-review develop` is a
ref. Quote it and it is content; leave it bare and it is syntax.

Unquoted arguments have no such protection, which is why quoting focus text is
the recommended form.

1. First token is **`doctor`** → run the **Doctor** health check below and stop.
   Ignore all other arguments.
2. **Split on the first bare `--`.** Everything *after* it is the **pathspec
   list** (path filters passed straight to `git diff`), never a target and never
   focus text. Everything before it continues through the steps below. The list
   is empty when there is no `--`.

   **Keep it as a LIST of separate arguments, not one joined string.**
   `-- src/ tests/` is *two* pathspecs. Flattening them into a single scalar and
   later expanding `-- $PATHSPEC` fails in **zsh**, which does not word-split
   unquoted expansions: git receives one pathspec literally named `src/ tests/`,
   matches nothing, and the empty-diff guard then aborts with "nothing to
   review" — a valid request rejected in a way that looks like a legitimate stop
   condition. (bash word-splits and happens to work, so this breaks only on the
   more common interactive shell.) Carry the list through and forward each entry
   as its own argument — see Step 3.

   **Do this before any other token matching** (but after Rule 0 sets quoted
   spans aside) — otherwise `-- src/` is swallowed as focus text and silently
   reviews the wrong thing.
   (`--comment`, `--focus`, `--save`, and `--working` are flags, not the bare
   `--` separator; do not split on them.)
3. **`--focus` — extract next, and take the WHOLE block.** Focus text is free
   prose, so it comes out ahead of every *mode* match below (steps 4–7);
   otherwise its own words get eaten as flags. Two forms:
   - **Quoted** — `--focus "…"` → take exactly the quoted span, however many
     lines or tokens it spans. Parsing then **resumes after the closing quote**,
     so other flags may appear on either side.
   - **Unquoted** — `--focus <text>` → consume **everything from after the flag
     to the end of the pre-`--` input**, not just the next token.

   Never consume only the first token after `--focus`. Given
   `/gemini-review --focus check retry logic`, taking just `check` would leave
   `retry` to be read as a **git ref** and `logic` as leftover focus — a review
   of the wrong target that still looks successful.

   Because the unquoted form runs to the end, **any other flag or target must
   come before it**: `/gemini-review 42 adversarial --focus <long text>`.
   Tokens *preceding* `--focus` are untouched and continue through the steps
   below. When in doubt, quote the focus text.
4. **`--save <path>`** → also write the review to `<path>` (see *Saving the
   review*). Remove the flag **together with** its single path argument.

   **A flag's argument is protected — claim it before any bare mode token is
   matched.** This step deliberately precedes `adversarial` and `--comment`
   below. Given `/gemini-review 42 --save adversarial`, matching modes first
   would strip `adversarial` as a mode switch, flipping the review to the
   hostile prompt *and* leaving `--save` with no path. The token immediately
   after `--save` is a filename, whatever it happens to spell.
5. **`adversarial`** (or **`adv`**) → use the **Adversarial review prompt**
   instead of the standard one. Remove the token. *(Matched only on what
   survives steps 3–4, so `adversarial` inside quoted focus text or as a
   `--save` filename stays content and does not switch modes.)*
6. **`--comment`** → after the review, **post the findings to the PR** (see
   *Posting to the PR*). Remove the token.
7. Of what remains: the **target** (Step 2), then any leftover is **focus
   text** (Step 2b), appended to anything `--focus` already supplied.

**Ordering invariant.** Steps 3–4 consume *flags that take arguments*; steps 5–6
match *bare tokens*. Argument-taking flags must always come first, so their
arguments are claimed before anything can mistake one for syntax. If a new flag
with an argument is ever added, it belongs in the 3–4 group, not after.

### Worked examples — the parse must produce exactly these

| input (after `/gemini-review`) | target | mode | pathspec | focus |
|---|---|---|---|---|
| *(empty)* | branch vs base | standard | — | — |
| `42 --comment` | PR 42 | standard | — | — |
| `develop -- src/` | `develop` | standard | `src/` | — |
| `"check retry logic"` | **branch vs base** | standard | — | `check retry logic` |
| `check retry logic` | **branch vs base** | standard | — | `check retry logic` |
| `--focus check retry logic` | branch vs base | standard | — | `check retry logic` |
| `42 --focus check retry logic` | PR 42 | standard | — | `check retry logic` |
| `--focus "check the adversarial path"` | branch vs base | **standard** | — | `check the adversarial path` |
| `adversarial --focus "the retry logic -- especially backoff"` | branch vs base | adversarial | **—** | `the retry logic -- especially backoff` |
| `"check the adversarial path -- especially backoff"` | branch vs base | **standard** | **—** | `check the adversarial path -- especially backoff` |
| `"develop"` | **branch vs base** | standard | — | `develop` |
| `42 adversarial --save r.md --focus "…"` | PR 42 | adversarial | — | `…` |
| `develop -- src/ tests/` | `develop` | standard | `src/` **+** `tests/` (two entries) | — |
| `42 --save adversarial` | PR 42 | **standard** | — | — (saves to file `adversarial`) |
| `wip -- src/` | **working tree** (`git diff HEAD`) | standard | `src/` | — |

Rows 4–5 are focus-only invocations: **prose with no target is valid** and falls
back to the branch diff — the prose must never be handed to `git diff` as a ref.
Rows 6–7 are what a naive tokenizer gets wrong: it would take only `check` and
then read `retry` as a git ref. Rows 8–10 are Rule 0 — `adversarial` and ` -- `
inside a quoted span must **not** change the mode or become a pathspec.

**Row 13** must stay *two* pathspec entries, never the single string
`src/ tests/` — see step 2. **Row 14** must stay a **standard** review saving to
a file literally named `adversarial`: the token after `--save` is a filename, not
a mode, which is why argument-taking flags are consumed first. **Row 15** must
diff the **working tree** (`git diff HEAD -- src/`), not `$BASE...HEAD -- src/`
— a pathspec narrows which files are reviewed, never which commits. Rows 3, 13
and 15 together are the check that target and pathspec **compose** instead of
one overriding the other.

**Row 10 is the trap.** It is the focus-only form with no `--focus` marker in
front of it, so a Rule 0 scoped to "spans after `--focus`" would leave it
unprotected: the mode would silently flip to adversarial and ` -- ` would become
a pathspec. Rule 0 covers *every* quoted span for exactly this reason. Row 11
shows the deliberate consequence — quoting a ref makes it focus text, because
quoting always means content.

**Echo the parse back before running.** State the target, mode, pathspec, and
whether focus text was found, in one line. Every failure mode above produces a
*plausible-looking* review of the wrong thing; showing the parse is what makes a
misread visible instead of silent.

## Core constraint

- This command is **review-only**. Do not fix issues, apply patches, or edit
  code. Exactly **two** write actions are permitted, each only when its flag was
  explicitly requested: writing the review to the path given by `--save`, and
  posting it to the PR with `--comment`. Both write the review and nothing else;
  neither ever modifies a source file.
- **Never pass `--dangerously-skip-permissions`.** That flag is the entire
  safety boundary — see *The safety model* below. `--mode plan` is **not** a
  read-only guarantee in `agy`; do not rely on it as one.
- Return the review's findings **verbatim** under a short header. Do not
  paraphrase, re-grade, or silently drop findings. You may add a one-line note
  at the end if a finding is clearly wrong, but never edit the model's text.

## The safety model — read this before changing any flag

`agy` differs from the old Gemini CLI in a way that matters:

- In headless (`--print`) mode, any tool needing permission — `read_file`,
  `write_file`, shell — is **auto-denied**, because there is no way to prompt.
  That denial is what makes this command safe to run unattended.
- `--dangerously-skip-permissions` removes that denial. With it, `agy` **will
  create and overwrite files even under `--mode plan`** (verified: plan mode
  wrote a new file and clobbered an existing one). Plan mode is a behavioral
  hint, not a sandbox.
- Consequence: this command **passes the whole diff inline in the prompt** and
  the model reads nothing from disk. That is simultaneously the safety story
  (no tool ever needs approval), the reliability story (no file-read loop to
  hang on), and the speed story.
- `--mode plan` is still passed as cheap defense-in-depth, but the guarantee
  comes from *omitting* `--dangerously-skip-permissions`.

## Doctor — `/gemini-review doctor`

A read-only health check. The point is to catch the confusing failure modes
*before* a real review. Run these and print a ✓/✗ checklist, with a one-line
remediation for each ✗; end with an overall **READY** / **NOT READY**.

1. **Installed?** `command -v agy` and `agy --version`. If missing:
   ```bash
   curl -fsSL https://antigravity.google/install.sh | bash   # macOS / Linux
   ```
   (Windows: `winget install Google.AntigravityCLI`.) `agy update` upgrades in
   place. If the user is migrating from the old Gemini CLI, `agy plugin import
   gemini` carries over their previous config.
2. **In a git repo?** `git rev-parse --is-inside-work-tree`.
3. **Auth and headless print mode actually work** (the end-to-end check static
   preflight can't do) — one tiny live call:
   ```bash
   agy -p 'Reply with exactly the token READY and nothing else.' \
     --mode plan --output-format text --print-timeout 90s
   ```
   - output contains `READY` → ✓ authenticated and headless print mode works.
   - **empty output** → *not* a hang. Read stderr: an auth failure, or a tool
     was auto-denied. See *Empty response* in Step 5.
   - **Do not judge this by the exit code** — `agy` exits `0` even on failure.
4. **A JSON parser for the success check** — **not optional**, because Step 5
   decides "did this review actually happen?" with it. If it is missing, the
   `.response` check silently degrades and an empty review can read as a clean
   one, which is precisely the failure this command exists to prevent.
   ```bash
   command -v jq || command -v python3
   ```
   - `jq` present → ✓ (preferred).
   - no `jq` but `python3` present → ✓, but **only with Step 5's exact
     one-liner**. Say which parser will be used, and verify it null-safe before
     declaring READY:
     ```bash
     printf '{"response":null}' | python3 -c 'import json,sys;print(json.load(sys.stdin).get("response") or "")'
     ```
     Must print an **empty line**. If it prints `None`, the command is using
     `.get("response", "")` — the wrong form — and a failed run will be reported
     as a review whose text is the word `None`. Fix the parser, not the doctor.
   - **neither** → ✗ **NOT READY**. Remediation: `brew install jq` (macOS) or
     `apt install jq`. Do not fall back to grepping the JSON by hand.
5. **`gh` for PR features** (optional — only needed for PR-number targets and
   `--comment`): `command -v gh` and `gh auth status`. Report as optional.

## Step 1 — Preflight (review modes)

- Confirm the `agy` binary is on PATH (`command -v agy`). If not, stop and tell
  the user to install it (command above) and authenticate (run `agy` once
  interactively). Suggest `/gemini-review doctor` to diagnose. Do not attempt
  the review without it.
- You must be inside a git repository. If not, stop and say so.

## Step 2 — Determine the review target from the remaining args

**This step decides the revision; Step 3 only adds path filters to it.** Record
which case matched — `$TARGET_KIND` is `branch`, `ref`, `wip`, or `pr`, plus
`$BASE` or `$REF` as applicable. Step 3 builds its `git diff` arguments from
that. Step 3 must never re-derive the revision or fall back to `$BASE`: a
pathspec narrows *which files* are reviewed, never *which commits*.

- **Empty** → review this branch's PR diff against its base. Detect the base:
  try the remote default branch
  (`git symbolic-ref --quiet refs/remotes/origin/HEAD` → strip to the branch
  name); if that fails, use `main`, then `master`. The diff is
  `git diff <base>...HEAD` (three-dot: merge-base to HEAD = exactly this
  branch's changes).
- **A bare integer** (e.g. `42`) → a GitHub PR. Use `gh pr diff 42` for the
  diff and `gh pr view 42` for the title/body so the reviewer has the intent.
  **`gh pr diff` takes no pathspec.** If the pathspec list is non-empty with a PR
  target, filter the diff *after* fetching it (e.g. `git apply --stat` style
  splitting, or `filterdiff`), or say plainly that the filter was not applied.
  Do not silently ignore it.
- **A git ref / branch name** (e.g. `develop`) → diff against it:
  `git diff <ref>...HEAD`.
- **`wip` or `--working`** → include uncommitted work: `git diff HEAD`
  (unstaged + staged vs HEAD). Use this when reviewing before committing.
- Anything left over after a target has been identified → **focus text**
  (see Step 2b). Focus text is *not* a target and never replaces one.
- **No target token at all, only prose** (e.g. `/gemini-review "check retry
  logic"`) → **default to this branch's diff against its base**, exactly as the
  Empty case above, and treat the prose as focus text. Focus text alone is a
  complete, supported invocation.

**Never let leftover prose become the target.** If nothing matched a target
rule, the answer is the default branch diff — *not* passing the prose to
`git diff` as a ref. A word like `check` is not a ref, so using it as one either
errors out or, worse, resolves to something unintended and reviews the wrong
thing. Default first; the prose is focus.

**The pathspec list was already split off in step 2 of the parse** and is *not* part
of the target. It applies on top of whichever target was selected, so
`/gemini-review develop -- src/` means "diff against `develop`, restricted to
`src/`". Every git-based target composes with it (the PR target is the one
exception, noted above). When the pathspec list is non-empty,
**say so in the report** and name what was excluded — a path filter is the
easiest way to make "reviewed" quietly overclaim.

**Tiebreak — applies to UNQUOTED tokens only.** A quoted span is already settled
by Rule 0: it is content, never a target, so it never reaches this test. For an
*unquoted* first token that is both a plausible git ref and plausible prose
(`main`, `master`, `test`), resolve it as a **ref** only when
`git rev-parse --verify --quiet <token>` succeeds *and* no other target was
given. Otherwise treat it as focus text. When ambiguous, say which reading you
used in the report so a misread is visible rather than silent.

This is also the escape hatch when the two readings collide: quote it to force
prose (`"main"` → focus), leave it bare to force the ref (`main` → target).

## Step 2b — Focus text (the highest-value lever)

Focus text is the single biggest quality lever this command has, and it
**composes with every target**. All of these are valid:

```
/gemini-review 42 "the nonce derivation and the hybrid rejection argument"
/gemini-review develop --focus "..."
/gemini-review wip --focus "..."
/gemini-review "..."                 # focus on the default branch diff
```

Accept focus text from either form:
- **`--focus <text>`** — explicit and the form to prefer whenever the text is
  long, multi-line, or could be mistaken for a ref. It takes the **entire**
  block (parse step 3), never just the next word.
- **Whatever remains** once mode tokens (`adversarial`, `--comment`) and the
  target have been consumed.

**Quoting.** `--focus "…"` is the robust form: the quoted span is lifted out
before any other matching, so focus prose containing words like `adversarial`,
`main`, or `wip` stays focus prose instead of silently switching the mode or
retargeting the review. Unquoted focus runs to the end of the input, so put any
other flag or the target *before* it.

**Focus text may be long and structured** — a multi-paragraph block with
numbered claims, specific file/section pointers, and named concerns is a
legitimate and effective input, not an abuse of the argument. Pass it through
**verbatim**, preserving line breaks and structure. Do not summarize, truncate,
or collapse it to one line.

**Focus ADDS priority; it never replaces the standard sweep.** This matters:
targeted and untargeted reviews find *different* defects, and neither is a
superset of the other. A focused run reliably hits what you pointed it at; the
standard sweep catches unrelated problems you did not know to ask about. Always
instruct the model to do both — see the focus block in Step 4.

## Step 3 — Gather the diff

- Produce the unified diff for the chosen target and a `--stat` summary.
- **Write the diff to a temp file, then HARD-CHECK it is non-empty before doing
  anything else. If the file has zero bytes, ABORT immediately** — report
  "nothing to review" and do **not** invoke `agy`. A path filter that matches
  no changes, a wrong base, or a bad glob produces an empty diff, and reviewing
  empty input yields a bogus "looks good". Treat empty input as a stop
  condition, never as "proceed".

  ```bash
  DIFF_FILE="$(mktemp)"; PROMPT_FILE="$(mktemp)"
  OUT="$(mktemp)"; ERR="$(mktemp)"
  trap 'rm -f "$DIFF_FILE" "$PROMPT_FILE" "$OUT" "$ERR"' EXIT

  # These come from the parse (Steps 1–2): TARGET_KIND is branch|ref|wip (a pr
  # target never reaches here), BASE/REF are revisions, PATHS holds one element
  # per pathspec.
  #
  # `:=` supplies a default ONLY when the parse left a value unset — it never
  # overwrites one. Plain assignment here would be a silent bug: `/gemini-review
  # wip` or `-- src/` would be reset to the default branch diff and then reviewed
  # under the requested target's name. An unset PATHS already counts 0, so it
  # needs no initialiser and must not be clobbered with `PATHS=()`.
  : "${TARGET_KIND:=branch}"
  : "${BASE:=main}"           # or the default branch detected in Step 2
  : "${REF:=}"                # set by the parse when TARGET_KIND=ref

  # STEP A — the TARGET selects the diff arguments. Never hard-code "$BASE" here:
  # the target may be an explicit ref, or `wip`, which is a TWO-dot working-tree
  # diff — a different form entirely, not just a different revision. Getting this
  # wrong reviews the default branch diff while reporting the requested target.
  case "$TARGET_KIND" in
    branch) set -- --text "$BASE...HEAD" ;;   # default: this branch vs its base
    ref)    set -- --text "$REF...HEAD" ;;    # /gemini-review develop
    wip)    set -- --text HEAD ;;             # /gemini-review wip (staged+unstaged)
    # A PR target never reaches here — it uses `gh pr diff` (Step 2).
  esac

  # STEP B — append the pathspecs, ONE ARGUMENT EACH, after a literal `--`.
  # Building one positional list keeps target and pathspec composed rather than
  # letting the pathspec branch re-decide the revision.
  #
  # Do NOT use a scalar. `-- $PATHSPEC` with PATHSPEC="src/ tests/" works in bash
  # (word splitting) but NOT in zsh, which passes one pathspec literally named
  # "src/ tests/". That matches nothing, so the guard below aborts with "nothing
  # to review" — a valid two-path request rejected as if it were empty.
  # Equally, `--` must stay its own word or git rejects the invocation outright.
  # The count guard also keeps "${PATHS[@]}" from being expanded when empty.
  if [ "${#PATHS[@]}" -gt 0 ]; then
    set -- "$@" -- "${PATHS[@]}"
  fi

  git diff "$@" | tr -d '\000' > "$DIFF_FILE"

  if [ ! -s "$DIFF_FILE" ]; then
    echo "nothing to review (empty diff for this target/pathspec)"; exit 0
  fi
  ```
- **Force a text diff and strip NUL bytes.** Use `git diff --text` so a file
  git considers "binary" (e.g. one with a stray NUL byte) still appears in the
  diff instead of collapsing to `Binary files differ` — otherwise that file is
  silently excluded from the review. Then pipe through `tr -d '\000'` before
  writing the temp file. If you had to strip bytes, mention it in the report.
- **Pass the temp file by its exact path** — do not re-glob for it
  (`/tmp/foo.*` may not match the name `mktemp` actually produced).

## Step 4 — Build the prompt (diff goes INLINE, not on stdin)

**`agy` ignores stdin.** The old `gemini ... -p "$PROMPT" < "$DIFF_FILE"` form
silently reviews nothing — the model receives no input and either invents a
review or returns empty. The diff must be embedded in the prompt string.

The focus block goes **before** the diff, not after it. A single trailing line
appended below a 90 KB diff is the weakest possible placement; a delimited block
stated up front is what the model actually steers on.

```bash
{
  printf '%s\n\n' "$REVIEW_PROMPT"
  if [ -n "$FOCUS" ]; then
    printf -- '--- PRIORITY FOCUS ---\n'
    printf '%s\n' "$FOCUS"          # verbatim: keep line breaks and structure
    printf -- '--- END PRIORITY FOCUS ---\n\n'
  fi
  printf -- '--- BEGIN DIFF ---\n'
  cat "$DIFF_FILE"
  printf -- '--- END DIFF ---\n'
} > "$PROMPT_FILE"
```

**Size guard — the prompt travels through `argv`.** `ARG_MAX` is ~1 MB
(args + environment combined), so a very large diff fails with "argument list
too long". Check before invoking and narrow rather than truncate:

```bash
PROMPT_BYTES=$(wc -c < "$PROMPT_FILE")
if [ "$PROMPT_BYTES" -gt 262144 ]; then
  echo "diff too large (${PROMPT_BYTES}B) — narrow with a pathspec or split the review"
  exit 0
fi
```

If it trips, re-run scoped to source paths (`/gemini-review <ref> -- <path>`)
or review the highest-risk files in separate passes — and say in the report
which files you covered and which you did not, so "reviewed" never overclaims.

**Note on convention files.** The model **cannot** read `AGENTS.md`,
`CLAUDE.md`, or `README` — those reads are auto-denied. Do not instruct it to.
If project conventions matter for this review, *you* read the relevant file and
inline a short summary into `$REVIEW_PROMPT` yourself.

## Step 5 — Run agy (read-only) and handle the result

```bash
agy -p "$(cat "$PROMPT_FILE")" \
  --mode plan \
  --output-format json \
  --print-timeout 10m \
  > "$OUT" 2>"$ERR"
```

Why these flags:
- **No `--dangerously-skip-permissions`** — the safety boundary. See *The
  safety model*. Never add it.
- `--mode plan` — defense-in-depth behavioral hint. Not a sandbox.
- `--output-format json` — gives a parseable envelope. `text` is fine for a
  quick call, but JSON is what makes the success check below reliable.
- `--print-timeout 10m` — **built-in watchdog**; replaces the hand-rolled
  `sleep`/`kill` wrapper the old Gemini version needed. Default is `5m`. Raise
  for a large diff; there is no need to background the run and poll it.

**Checking success — the exit code is useless.** `agy` returns **`0` even on
total failure**, and `"status":"SUCCESS"` appears in the JSON *even when the run
produced nothing*. The only reliable signal is **a non-empty `.response`**:

```bash
# Pick EXACTLY ONE parser. These are alternatives, not a sequence — running both
# unconditionally means the second silently overwrites the first, and on a
# jq-only box the python3 line yields "" and reports a successful review as a
# failure.
if command -v jq >/dev/null 2>&1; then
  # `// ""` coalesces BOTH a missing key and an explicit null.
  RESPONSE="$(jq -r '.response // ""' "$OUT")"
elif command -v python3 >/dev/null 2>&1; then
  # Note `or ""`, NOT `.get("response", "")`. The default in .get() applies only
  # when the key is ABSENT. On {"response": null} it returns None, print() emits
  # the literal string "None", and the -z test below then reads that as a
  # successful review — printing, saving, and posting "None" as the findings.
  RESPONSE="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("response") or "")' "$OUT")"
else
  # Cannot verify the run happened, so do not present its output as a review.
  echo "no JSON parser (jq or python3) — cannot verify the review; see /gemini-review doctor"
  exit 1
fi
# Backstop: a response that is exactly "None"/"null" is a parser artifact, not a
# review. Cheap insurance if the parser above is ever edited back to a form that
# stringifies null.
case "$RESPONSE" in
  None|null|nil) echo "parser artifact (\"$RESPONSE\") — treating as no review"; RESPONSE="" ;;
esac

if [ -z "$RESPONSE" ]; then
  echo "agy produced no review. Cause:"; cat "$ERR"
  exit 1     # STOP here — never fall through and print an empty review
fi
```

An empty `$RESPONSE` is a **stop condition**. Do not continue to the reporting
step and emit a review header with nothing under it — that reads as "reviewed,
found nothing" when in fact nothing was reviewed. Report the failure instead.

- **On success** — print a header (`# Gemini Review — <target>`, or
  `# Gemini Adversarial Review — <target>` in adversarial mode), then
  **`$PROVENANCE`** (defined just below), then `$RESPONSE` **verbatim**.

**Record the model yourself — the envelope does not carry it.** The JSON is
exactly `conversation_id`, `status`, `response`, `duration_seconds`,
`num_turns`, `usage`. There is **no `model` field**, so which model produced a
review is unrecoverable after the fact unless the command writes it down. Track
what you passed and state it in the report and in any saved/posted copy:

```bash
MODEL="${MODEL:-<agy default>}"    # whatever you passed to --model, or the default
EFFORT="${EFFORT:-<agy default>}"
```

### The canonical provenance block — `$PROVENANCE`

Build this **once** and reuse it verbatim in **every** output: the inline
report, the `--save` file, and the `--comment` body. It is defined here, in one
place, on purpose — the saved and posted copies are easy to drift apart, and a
posted finding with no provenance is exactly the one someone will question.

```markdown
🔭 Read-only second opinion via the Antigravity CLI (`agy`) — automated, advisory.

- target: <target>   · pathspec: <value or none>
- model: <MODEL>     · effort: <EFFORT>
- mode: standard | adversarial   · focus: yes/no
- reviewed: <N> files, <N> lines   · duration: <duration_seconds>s
```

Referred to as **`$PROVENANCE`** throughout the rest of this file. A review
whose model is unknown cannot be compared against a later one, and "which model
said this?" is the first question anyone asks about a surprising finding — which
is most likely to be asked about the copy posted to a PR, where the reader was
not present for the run.
- **Empty response** → read `$ERR`, which carries the real diagnostic:
  - *"a tool required the `read_file` permission … auto-denied"* → the prompt
    told the model to open files. Reinforce the "judge from the diff alone"
    clause; do **not** "fix" this with `--dangerously-skip-permissions`.
  - **auth failure** → run `agy` once interactively to sign in.
  - **timeout** → raise `--print-timeout`, or narrow the diff.
- Do not fix any issue the review raises. Surfacing them is the job; the user
  decides what to act on.

**Speed — it scales sub-linearly, so do not pre-emptively narrow.** Measured:

| prompt | time | output |
|---|---|---|
| ~10 KB (~250 lines) | ~12–16 s | ~2 KB |
| ~98 KB | ~46 s | ~15 KB (78 K in, 10 K thinking, 15 K out) |

**10× the input costs about 3× the time.** A large diff is far cheaper than the
linear estimate suggests, so run the whole thing first and narrow only if it
actually drags. Just run it and wait; there is no need to background it. Levers
if one does drag:
- **Faster model:** `--model gemini-3.6-flash-medium` (see `agy models` for the
  current list; `gemini-3.1-pro-high` is the high-reasoning end).
- **Reasoning effort:** `--effort low|medium|high` — `high` for a small,
  high-stakes change; `low` for a large mechanical one.
- **Narrow the diff** to source paths, skipping docs, lockfiles, and generated
  code; note in the report what you scoped out.

Pick the prompt by mode:

### Standard review prompt

```
You are a meticulous senior code reviewer. A unified git diff is provided below
between the BEGIN DIFF / END DIFF markers. Review ONLY that change.

Judge the change from the diff ALONE. Do NOT attempt to open, read, or list any
files — you are in a read-only sandbox where file access is denied, and trying
will waste the run. The diff is the complete source of truth.

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
You are a hostile, adversarial code reviewer. A unified git diff is provided
below between the BEGIN DIFF / END DIFF markers. Assume the change is guilty
until proven innocent — your goal is to MAKE IT FAIL, not to praise it.

Judge the change from the diff ALONE. Do NOT attempt to open, read, or list any
files — you are in a read-only sandbox where file access is denied, and trying
will waste the run. The diff is the complete source of truth.

Attack the diff along every axis:
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

### Focus clause — append to whichever prompt was chosen

Only when `$FOCUS` is non-empty. Append this to the prompt text; the focus
content itself goes in the `--- PRIORITY FOCUS ---` block (Step 4), not here.

```
A PRIORITY FOCUS block is provided above the diff. Treat every item in it as a
first-class review target: address each one explicitly, by name, and say so
directly if you find no problem with it.

The focus block ADDS priorities — it does not narrow your scope. Still perform
the full review described above and report unrelated defects you find along the
way. A finding that nobody asked about is worth more, not less.
```

**Why additive.** Focused and unfocused runs surface *different* defects and
neither subsumes the other: an unfocused pass has caught a genuine CRITICAL and
a cross-document citation inconsistency that a focused pass missed, while the
focused pass caught two substantive reasoning errors the unfocused pass never
reached. Suppressing the general sweep to honor the focus would trade one set of
real findings for another instead of getting both.

## Saving the review (`--save <path>`)

Only when `--save` was explicitly given. A review that exists only in scrollback
is gone the moment the session ends, and `--comment` is not a substitute — it
requires a PR to exist, and not every review has one. `--save` writes the same
verbatim output to a file with the same provenance header.

This is a **write, but a narrow one**: it **creates** a single new file and
touches nothing else. It **never overwrites an existing file** — see the
clobber rule below, which is a hard stop, not a preference. That matters
because `<path>` is arbitrary user input: pointed at a source file or a doc, an
overwriting `--save` would destroy it, which no "review-only" command may ever
do. It still **never edits code**.

**Resolve the destination first, then check for clobbering.** Order matters: a
directory *always* exists, so testing "does `<path>` exist?" before testing
"is it a directory?" makes the directory case unreachable — every
`--save ~/reviews/` would stop with "that already exists" instead of writing
inside it.

1. **Resolve `<path>` to a single output file, `$OUT_PATH`.**
   - **`<path>` is an existing directory** → write
     `gemini-review-<slug>-<timestamp>.md` *inside* it, where `<slug>` is the
     target **made filename-safe first**.

     Targets are routinely branch names containing slashes (`feature/foo`,
     `release/v1.2.3`). Interpolating one raw turns the slash into a **path
     separator**, so the write either fails on a missing intermediate directory
     or silently lands somewhere other than the file you meant:

     ```bash
     SLUG="$(printf '%s' "$TARGET" | tr '/ :~^?*[]\\' '-' | tr -s '-' | sed 's/^-*//; s/-*$//')"
     : "${SLUG:=review}"          # empty/degenerate target must not yield a dotfile or bare -.md
     OUT_PATH="$SAVE_DIR/gemini-review-${SLUG}-$(date +%Y%m%d-%H%M%S).md"
     ```

     This collapses path separators and other path-hostile characters to `-`, so
     `feature/foo` becomes `gemini-review-feature-foo-<ts>.md` and the result is
     always a single file directly inside `<path>`.
   - **Otherwise** → `OUT_PATH="<path>"`, taken literally.

   The timestamp means the directory form is inherently non-clobbering: repeated
   saves into the same directory accumulate rather than overwrite.
2. **Never overwrite — checked against `$OUT_PATH`, not `<path>`.** If
   `$OUT_PATH` already exists, do **not** write to it. There is no "unless" and
   no prompt-and-proceed: either report the existing path and stop, or write to
   a non-colliding sibling (append `-2`, `-3`, … before the extension) and say
   which path you actually used.

   ```bash
   if [ -e "$OUT_PATH" ]; then
     echo "refusing to overwrite existing file: $OUT_PATH"; exit 1
   fi
   ```

   `<path>` is arbitrary user input. A typo or a stale shell completion can
   point it at a source file, and a review tool that silently replaces one has
   done far more damage than failing to save. The user asked to keep a review,
   not to lose a file.
3. Write the title, then **`$PROVENANCE`**, then `$RESPONSE` **verbatim**:
   ```markdown
   # Gemini Review — <target>

   <$PROVENANCE — see Step 5 for the canonical block>

   <$RESPONSE, verbatim>
   ```
   Use the block exactly as defined in Step 5; do not re-derive a shorter one
   here. A saved review with no model or target recorded is nearly worthless six
   weeks later.
4. **Never write on an empty `$RESPONSE`.** Step 5 already treats that as a hard
   stop; saving an empty review to disk turns a transient failure into a durable
   artifact that reads like a clean pass.
5. Report the path you wrote back to the user.

`--save` and `--comment` compose — with both, write the file *and* post, from
the same `$RESPONSE`, so the two copies cannot disagree.

## Posting to the PR (`--comment`)

Only when `--comment` was explicitly given. This is the one *externally
visible* write the command makes; it still **never edits code**.

1. Resolve the PR number: if the target was a PR number, use it; otherwise find
   the PR for the current branch (`gh pr view --json number,url`). If there is
   no open PR, do **not** post — show the review and say no PR was found.
2. Post **`$PROVENANCE`** followed by `$RESPONSE` **verbatim**, via:
   ```bash
   gh pr comment <PR#> --body-file <file>
   ```
   Comment body layout — the **same** block `--save` writes, not a shortened
   one-line variant:
   ```markdown
   <$PROVENANCE — see Step 5 for the canonical block>

   <$RESPONSE, verbatim>
   ```
   The posted copy is the one that most needs provenance: its readers were not
   present for the run, cannot see which model or effort produced it, and have
   no way to recover that later (the JSON envelope has no `model` field). A PR
   comment asserting a CRITICAL with no attribution is the hardest kind to act
   on.
3. Report the resulting comment URL back to the user.
4. If `gh` is missing or unauthenticated, skip posting, show the review inline,
   and tell the user (`/gemini-review doctor` checks `gh`).
