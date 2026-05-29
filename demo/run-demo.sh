#!/usr/bin/env bash
# Representative output for the README demo GIF (see gemini-review.tape).
# This is NOT a live Gemini call — a real review takes ~80s+ and is
# non-deterministic, which makes a poor looping GIF. The text below mirrors
# the shape of an actual `/gemini-review adversarial` result: hostile framing,
# a concrete failing scenario per finding, ending in a one-line verdict.
set -euo pipefail

dim=$'\033[2m'; bold=$'\033[1m'; reset=$'\033[0m'
red=$'\033[91m'; yel=$'\033[33m'; grn=$'\033[32m'

printf '%s\n' "${dim}↳ running gemini --skip-trust --approval-mode plan (read-only)…${reset}"
sleep 1.4
printf '\n%s\n' "${bold}# Gemini Adversarial Review — PR #42${reset}"
sleep 0.3

printf '\n%s\n'   "${bold}### CRITICAL${reset}"
printf '%s\n'     "  ${grn}none${reset}"
sleep 0.2
printf '\n%s\n'   "${bold}${red}### HIGH${reset}"
printf '%s\n'     "  ${red}•${reset} ${bold}src/runner.ts:118${reset} — unbounded child-output buffering"
printf '%s\n'     "    ${dim}trigger:${reset} a probe looping ${bold}echo${reset} floods stdout; the parent buffers"
printf '%s\n'     "    every byte and is OOM-killed before the probe ever exits."
printf '%s\n'     "    ${dim}fix:${reset} cap capture per stream, append a truncation marker."
sleep 0.2
printf '\n%s\n'   "${bold}${yel}### MEDIUM${reset}"
printf '%s\n'     "  ${yel}•${reset} ${bold}src/runner.ts:151${reset} — no per-probe timeout"
printf '%s\n'     "    ${dim}trigger:${reset} a hung probe (${bold}sleep 1d${reset}) blocks the whole run forever."
printf '%s\n'     "    ${dim}fix:${reset} enforce a timeout; SIGKILL on expiry."
sleep 0.4
printf '\n%s\n'   "${bold}Verdict:${reset} ${yel}fix-before-merge${reset} — the OOM path is the blocker."
sleep 1.2
