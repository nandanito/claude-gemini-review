# VHS tape for the README demo GIF.
#   Render:  vhs demo/gemini-review.tape   (writes demo/gemini-review.gif)
# Run from the repo root.
#
# Shows invoking the command and the verbatim, severity-sorted result. The
# output is representative (see run-demo.sh) — a real review is ~80s and
# non-deterministic, which makes a poor looping GIF.
#
# Trick: the leading "/" of the command lives in the prompt (PS1='claude > /'),
# and a tiny PATH shim named `gemini-review` execs the demo. So the screen
# reads `claude > /gemini-review 42` while bash runs a real, resolvable command.

Output demo/gemini-review.gif

Set Shell bash
Set FontSize 20
Set Width 1100
Set Height 600
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type `mkdir -p /tmp/grbin && printf '#!/usr/bin/env bash\nexec bash demo/run-demo.sh\n' > /tmp/grbin/gemini-review && chmod +x /tmp/grbin/gemini-review` Enter
Type `export PATH=/tmp/grbin:$PATH; PS1='claude > /'; clear` Enter
Show

Sleep 700ms
Type "gemini-review 42"
Sleep 900ms
Enter
Sleep 9s
