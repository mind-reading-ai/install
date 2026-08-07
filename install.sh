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

  # 1) prereqs the DOWNLOAD needs (the onboarder re-checks its own, incl. docker).
  #    7d rehearsal finding (Roy 08-06): a fresh Linux box fails three separate
  #    prereq hurdles before the one real command — on apt systems, OFFER to
  #    close the gap right here (never silently: the machine is the client's).
  local missing=()
  for cmd in gh tar node; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
      echo "  MISSING: $cmd is not installed." >&2
      missing+=("$cmd")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    offer_prereq_install "${missing[@]}"
    # the offer path returns only after installing — re-verify honestly
    local still=0
    for cmd in "${missing[@]}"; do
      if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "  STILL MISSING after install: $cmd — install it yourself, then retry." >&2
        still=1
      fi
    done
    if [ "$still" = "1" ]; then exit 1; fi
  fi
  # 1b) GitHub login — the auth MOMENT stays human (browser device-code);
  #     the CEREMONY folds in (7d, Roy 08-06: "shouldn't it fold into the
  #     one-liner too?"). Run the login right here on the real terminal;
  #     no terminal to run it on = honest stop with the manual command.
  if ! gh auth status > /dev/null 2>&1; then
    echo "  You're not logged into GitHub yet — that's how you access the (private) product."
    # Pre-answer gh's wizard (Roy 08-06: "fold all the answers to the script");
    # the flags ARE the answers — github.com / HTTPS / browser device-code.
    # --scopes read:packages: the engine IMAGE is a GitHub package; a default
    # login token gets 403'd at the registry (live-caught, 7d rehearsal step 7).
    # The one surviving human moment: the browser code click.
    local login_args=(--hostname github.com --git-protocol https --web --scopes read:packages)
    if [ "${INSTALL_SH_STDIN_OK:-}" = "1" ]; then
      gh auth login "${login_args[@]}" || manual_auth_stop
    elif (: < /dev/tty) 2> /dev/null; then
      echo "  Starting the login now (a browser code will appear)..."
      gh auth login "${login_args[@]}" < /dev/tty || manual_auth_stop
    else
      manual_auth_stop
    fi
    # re-verify honestly — a cancelled login must not limp forward
    gh auth status > /dev/null 2>&1 || manual_auth_stop
  fi
  # Already-logged-in tokens may still lack the packages scope (the 7d
  # rehearsal's exact case: logged in mid-run, 403'd at the registry two
  # steps later). Heal inline — same fold-the-ceremony rule; browser click
  # again, or an honest stop when there's no terminal to ask on.
  if ! gh auth status 2>&1 | grep -q ':packages'; then
    echo "  Your GitHub login is missing the 'read packages' permission (needed to download the engine)."
    if [ "${INSTALL_SH_STDIN_OK:-}" = "1" ]; then
      gh auth refresh -s read:packages || manual_scope_stop
    elif (: < /dev/tty) 2> /dev/null; then
      echo "  Adding it now (browser code again)..."
      gh auth refresh -s read:packages < /dev/tty || manual_scope_stop
    else
      manual_scope_stop
    fi
    gh auth status 2>&1 | grep -q ':packages' || manual_scope_stop
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

# 7d: offer to install missing prereqs via apt (Ubuntu/Debian class). Consent
# is asked on the REAL terminal (stdin is the curl pipe); default = yes.
# Anywhere we can't ask or can't act -> manual_prereq_stop, the honest exit.
offer_prereq_install() {
  if ! command -v apt-get > /dev/null 2>&1; then manual_prereq_stop "$@"; fi
  if ! command -v sudo > /dev/null 2>&1; then manual_prereq_stop "$@"; fi
  local answer=""
  if [ "${INSTALL_SH_STDIN_OK:-}" = "1" ]; then
    read -r answer || answer="" # test seam: consent arrives on the pipe
  elif (: < /dev/tty) 2> /dev/null; then
    printf "  Install them now with apt-get? [Y/n] " > /dev/tty
    read -r answer < /dev/tty || answer=""
  else
    manual_prereq_stop "$@" # no terminal to ask on — never install unasked
  fi
  case "$answer" in
    n* | N*) manual_prereq_stop "$@" ;;
  esac
  echo "  installing: $* ..."
  # R1 MINOR-4: under set -e a curl/apt failure here would kill the script
  # mid-line with no guidance — every failure path in this file must end at
  # an honest stop that names the retry.
  sudo apt-get update -qq || manual_prereq_stop "$@"
  local m apt_pkgs=()
  for m in "$@"; do
    case "$m" in
      # Ubuntu's default nodejs is older than the onboarder's floor — NodeSource 22
      node)
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - > /dev/null || manual_prereq_stop "$@"
        apt_pkgs+=(nodejs)
        ;;
      *) apt_pkgs+=("$m") ;;
    esac
  done
  sudo apt-get install -y "${apt_pkgs[@]}" || manual_prereq_stop "$@"
}

manual_auth_stop() {
  echo "" >&2
  echo "  GitHub login didn't complete. Log in, then paste the install command again:" >&2
  echo "    gh auth login --scopes read:packages" >&2
  exit 1
}

manual_scope_stop() {
  echo "" >&2
  echo "  Couldn't add the 'read packages' permission. Add it, then paste the install command again:" >&2
  echo "    gh auth refresh -s read:packages" >&2
  echo "  (If gh says it can't refresh — e.g. you authenticate via a GITHUB_TOKEN env var or a" >&2
  echo "   fine-grained token — mint that token with the packages read permission instead.)" >&2
  exit 1
}

manual_prereq_stop() {
  echo "" >&2
  if command -v apt-get > /dev/null 2>&1; then
    echo "  Install the missing tool(s), then paste the install command again:" >&2
    local m
    for m in "$@"; do
      case "$m" in
        node) echo "    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs" >&2 ;;
        *) echo "    sudo apt-get install -y $m" >&2 ;;
      esac
    done
  else
    echo "  Install the missing tool(s) above, then paste the install command again." >&2
  fi
  exit 1
}

main "$@"
