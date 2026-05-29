#!/usr/bin/env bash
# Representative output for the README demo GIF (see gemini-review.tape).
# This is NOT a live Gemini call — a real review takes ~80s+ and is
# non-deterministic, which makes a poor looping GIF. The text below mirrors
# the shape of an actual `/gemini-review` result: a verbatim, severity-sorted
# report ending in a one-line verdict.
set -euo pipefail

dim=$'\033[2m'; bold=$'\033[1m'; reset=$'\033[0m'
red=$'\033[91m'; yel=$'\033[33m'; grn=$'\033[32m'; cyn=$'\033[36m'

printf '%s\n' "${dim}↳ running gemini --skip-trust --approval-mode plan (read-only)…${reset}"
sleep 1.4
printf '\n%s\n' "${bold}# Gemini Review — PR #42${reset}"
sleep 0.3

printf '\n%s\n'   "${bold}### CRITICAL${reset}"
printf '%s\n'     "  ${grn}none${reset}"
sleep 0.2
printf '\n%s\n'   "${bold}### HIGH${reset}"
printf '%s\n'     "  ${grn}none${reset}"
sleep 0.2
printf '\n%s\n'   "${bold}${yel}### MEDIUM${reset}"
printf '%s\n'     "  ${yel}•${reset} ${bold}src/runner.ts:118${reset} — child stdout/stderr buffered"
printf '%s\n'     "    without bound; a runaway probe can exhaust memory."
printf '%s\n'     "    ${dim}fix:${reset} cap capture per stream and append a truncation marker."
sleep 0.2
printf '\n%s\n'   "${bold}### LOW${reset}"
printf '%s\n'     "  ${cyn}•${reset} ${bold}src/cli.ts:64${reset} — value flags swallow the next"
printf '%s\n'     "    ${dim}--flag${reset} as their value; reject missing values."
sleep 0.4
printf '\n%s\n'   "${bold}Verdict:${reset} ${yel}fix-before-merge${reset} — 1 medium, 1 low; no blockers."
sleep 1.2
