#!/usr/bin/env bash
# install.sh — the org-brain ONE-COMMAND client installer (backlog #103).
#
#   curl -fsSL https://raw.githubusercontent.com/mind-reading-ai/install/main/install.sh | bash
#
# This script is PUBLIC and holds no secrets: it is fetch-and-run logic only.
# The PRODUCT is private — the download below succeeds only for GitHub
# accounts granted access to the factory repo, using the client's own `gh`
# login (the single auth point; the script never touches tokens).
#
# SOURCE OF TRUTH: tools/install.sh in the factory repo (reviewed + tested
# there); tools/release-runtime.sh copies it to the public repo on every
# runtime release. Do not edit the public copy by hand.
#
# Design notes (the traps are designed in, not discovered):
# - Everything lives in main() and the LAST LINE calls it — a half-downloaded
#   script parses to a no-op instead of executing half an installer.
# - Under `curl | bash` STDIN IS THE PIPE, and the onboarder is interactive:
#   we re-attach the terminal via </dev/tty. No tty (CI, exotic terminals) =
#   honest stop that prints the manual three-command fallback.
set -euo pipefail

FACTORY_REPO="${FACTORY_REPO:-mind-reading-ai/ai-native-org}"
# script-level (NOT local): the EXIT trap below runs after main's locals are
# gone — a `local tmp` + set -u turns successful runs into exit-1 at cleanup.
TMP_DIR=""

main() {
  echo ""
  echo "=== org-brain installer ==="
  echo ""

  # 1) prereqs the DOWNLOAD needs (the onboarder re-checks its own, incl. docker)
  local missing=0
  for cmd in gh tar node; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
      echo "  MISSING: $cmd is not installed." >&2
      missing=1
    fi
  done
  if [ "$missing" = "1" ]; then
    echo "" >&2
    echo "  Install the missing tool(s) above, then paste the install command again." >&2
    exit 1
  fi
  if ! gh auth status > /dev/null 2>&1; then
    echo "  gh is not authenticated — this is how you access the (private) product." >&2
    echo "" >&2
    echo "  Fix, then paste the install command again:" >&2
    echo "    gh auth login" >&2
    exit 1
  fi

  # 2) the onboarder is INTERACTIVE — without a terminal to re-attach, stop
  #    honestly and print the manual path (never limp into eaten prompts).
  #    INSTALL_SH_STDIN_OK=1 is the TEST seam (drives the download/hand-off
  #    legs from a harness that has no terminal): documented, off by default.
  if [ "${INSTALL_SH_STDIN_OK:-}" != "1" ] && ! (: < /dev/tty) 2> /dev/null; then
    no_tty_fallback
  fi

  # 3) download the onboarder from the newest runtime release (client's gh auth)
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/org-brain-install-XXXXXX")"
  trap 'rm -rf "$TMP_DIR"' EXIT
  echo "  downloading the onboarder (release: latest) ..."
  if ! gh release download --repo "$FACTORY_REPO" --pattern onboarder.tar.gz --dir "$TMP_DIR" 2> "$TMP_DIR/dl-err.txt"; then
    echo "  DOWNLOAD FAILED:" >&2
    sed 's/^/    /' "$TMP_DIR/dl-err.txt" >&2
    echo "  Your GitHub account may not have access to $FACTORY_REPO yet — ask us to grant it." >&2
    exit 1
  fi
  tar -xzf "$TMP_DIR/onboarder.tar.gz" -C "$TMP_DIR"
  echo "  onboarder ready."
  echo ""

  # 4) hand off to the interactive onboarder with the REAL terminal attached
  if [ "${INSTALL_SH_STDIN_OK:-}" = "1" ]; then
    node "$TMP_DIR/onboard.js"
  else
    node "$TMP_DIR/onboard.js" < /dev/tty
  fi
}

no_tty_fallback() {
  echo "  No interactive terminal available (the onboarder asks questions)." >&2
  echo "" >&2
  echo "  Run it manually instead:" >&2
  echo "    gh release download --repo $FACTORY_REPO --pattern onboarder.tar.gz" >&2
  echo "    mkdir onboarder && tar -xzf onboarder.tar.gz -C onboarder" >&2
  echo "    node onboarder/onboard.js" >&2
  exit 2
}

main "$@"
