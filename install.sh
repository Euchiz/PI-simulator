#!/usr/bin/env bash
# Install the `lab` CLI by symlinking bin/ onto your PATH. Data lives in $LAB_HOME, not here.
set -euo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DEST="${1:-$HOME/.local/bin}"
mkdir -p "$DEST"
n=0
for f in "$SELF"/bin/*; do
  [ -f "$f" ] || continue
  chmod +x "$f"
  ln -sf "$f" "$DEST/$(basename "$f")"
  n=$((n+1))
done
echo "linked $n commands -> $DEST"
case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo "NOTE: $DEST is not on your PATH. Add:  export PATH=\"$DEST:\$PATH\"" ;;
esac
echo
echo "next:"
echo "  lab init ~/lab                 # create the blackboard"
echo "  export LAB_HOME=~/lab          # add to your shell rc"
echo "  lab register <name> [path]     # one per session"
echo "  lab help"
