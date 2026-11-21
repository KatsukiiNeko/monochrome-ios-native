#!/usr/bin/env bash
# scripts/package-ipa.sh: wrap a built Monochrome.app into an unsigned IPA.
set -euo pipefail
APP="$(realpath "${1:?usage: package-ipa.sh <path/to/Monochrome.app> <out.ipa>}")"
OUT="$(realpath -m "${2:?usage: package-ipa.sh <path/to/Monochrome.app> <out.ipa>}")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Payload"
cp -R "$APP" "$work/Payload/"
payload="$(echo "$work"/Payload/*.app)"
rm -rf "$payload"/_CodeSignature "$payload"/embedded.mobileprovision

binary="$(basename "$payload" .app)"
# Debug info and linker rpaths carry the builder's absolute toolchain path;
# neither is needed once the app links the system Swift runtime. Extensions are
# separate executables and need the same treatment.
strip_binary() {
  local target="$1"
  llvm-strip --strip-debug "$target"
  llvm-otool -l "$target" | awk '/LC_RPATH/{seen=1} seen&&/path /{print $2; seen=0}' |
    while read -r rpath; do
      case "$rpath" in
        "$HOME"/*) llvm-install-name-tool -delete_rpath "$rpath" "$target" ;;
      esac
    done
}
strip_binary "$payload/$binary"
for appex in "$payload"/PlugIns/*.appex; do
  [ -d "$appex" ] || continue
  name="$(basename "$appex" .appex)"
  [ -f "$appex/$name" ] || continue
  strip_binary "$appex/$name"
done

mkdir -p "$(dirname "$OUT")"
(cd "$work" && zip -qry "$OUT" Payload)
echo "wrote $OUT"
