#!/bin/bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$DIR")"
PLUGIN="$DIR/stagethumbs"
SO="$PLUGIN/stagethumbs.so"
STAMP="$PLUGIN/.built-for"
LOADED="$PLUGIN/.loaded"
lua_quote() { local s=${1//\\/\\\\}; printf "'%s'" "${s//\'/\\\'}"; }
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-tableau"
# hyprctl exits 0 even when the Lua fails and prints the error instead of "ok", so a
# layout that didn't load is written down and shown once, not lost
load_tableau() {
  local out
  out=$(hyprctl eval "_G.tableau_runtime = true; dofile($(lua_quote "$DIR/tableau.lua")); dofile($(lua_quote "$ROOT/tableau.lua"))" 2>&1)
  # warnings and notes ("warning: ...", "info: ...") mean the Lua ran; only errors count
  [[ $out == ok ]] && return 0
  [[ -n $out ]] && ! grep -qE '^error|only supported' <<<"$out" && return 0
  [[ ${1:-} == quiet ]] && return 1   # the first try at start; the second one reports
  mkdir -p "$STATE" && printf '%s load: %s\n' "$(date '+%F %T')" "${out:0:2000}" >>"$STATE/errors.log"
  notify-send -a Tableau "Tableau's layouts didn't load" "${out:0:300}" 2>/dev/null || true
  return 1
}
load_workspace_layouts() {
  local file="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/omarchy-workspace-layout.lua"
  [[ -f $file ]] || return 0
  hyprctl eval "dofile($(lua_quote "$file"))" >/dev/null
}
build_thumbs() {
  local version want have
  version=$(pacman -Q hyprland 2>/dev/null | awk '{ print $2 }')
  [[ -n $version ]] || return 0
  want="$version $(md5sum "$PLUGIN/main.cpp" | cut -c1-12)"
  have=$(cat "$STAMP" 2>/dev/null)
  [[ $want == "$have" ]] && return 0
  if ! command -v make >/dev/null || ! command -v g++ >/dev/null || ! pkg-config --exists hyprland 2>/dev/null; then echo "$want" >"$STAMP"; return 0; fi
  if make -B -C "$PLUGIN" >"$PLUGIN/build.log" 2>&1; then echo "$want" >"$STAMP"; else rm -f "$SO"; echo "$want" >"$STAMP"; notify-send -a Tableau "Thumbnail helper unavailable" "Install base-devel to build Tableau's adaptive miniature thumbnails." 2>/dev/null || true; fi
}
load_thumbs() {
  [[ -f $SO && -f $STAMP ]] || return 0
  local target previous
  target="$PLUGIN/tableau-thumbs-$(md5sum <"$STAMP" | cut -c1-12).so"
  [[ -f $target ]] || cp -f "$SO" "$target"
  previous=$(cat "$LOADED" 2>/dev/null)
  if hyprctl plugin list 2>/dev/null | grep -q '^Plugin stagethumbs '; then [[ $previous == "$target" ]] && return 0; hyprctl plugin unload "${previous:-$SO}" >/dev/null; sleep 0.3; fi
  hyprctl plugin load "$target" >/dev/null || return 0
  echo "$target" >"$LOADED"
  # every build leaves a copy behind; keep only the one in use
  local old
  for old in "$PLUGIN"/tableau-thumbs-*.so "$PLUGIN"/orbit-thumbs-*.so; do
    [[ -f $old && $old != "$target" ]] && rm -f -- "$old"
  done
  sleep 0.5
}
case "${1:-start}" in
  start) load_tableau quiet; build_thumbs; load_thumbs; load_tableau; load_workspace_layouts ;;
  load) load_tableau; load_workspace_layouts ;;
  stop) hyprctl reload >/dev/null ;;
  *) echo "usage: $0 start|load|stop" >&2; exit 1 ;;
esac
