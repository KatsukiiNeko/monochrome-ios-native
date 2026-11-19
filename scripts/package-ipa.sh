#!/usr/bin/env bash
# scripts/package-ipa.sh: wrap a built Monochrome.app into an unsigned IPA.
set -euo pipefail
APP="${1:?usage: package-ipa.sh <path/to/Monochrome.app> <out.ipa>}"
OUT="$(realpath -m "${2:?usage: package-ipa.sh <path/to/Monochrome.app> <out.ipa>}")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Payload"
cp -R "$APP" "$work/Payload/"
rm -rf "$work"/Payload/*.app/_CodeSignature "$work"/Payload/*.app/embedded.mobileprovision
mkdir -p "$(dirname "$OUT")"
(cd "$work" && zip -qry "$OUT" Payload)
echo "wrote $OUT"
