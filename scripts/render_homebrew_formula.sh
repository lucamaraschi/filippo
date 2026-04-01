#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "usage: $0 <version> <url> <sha256> [output-path]" >&2
  exit 1
fi

version="$1"
url="$2"
sha256="$3"
output_path="${4:-}"
template_path="$(cd "$(dirname "$0")/.." && pwd)/homebrew/filippo.rb"

rendered="$(
  sed \
    -e "s|__VERSION__|${version}|g" \
    -e "s|__URL__|${url}|g" \
    -e "s|__SHA256__|${sha256}|g" \
    "$template_path"
)"

if [[ -n "$output_path" ]]; then
  printf "%s\n" "$rendered" > "$output_path"
else
  printf "%s\n" "$rendered"
fi
