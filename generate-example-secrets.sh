#!/usr/bin/env bash

# note: this script ASSUMES `secrets.nix` exists; it's intended to ensure
#       that the EXAMPLE file stays aligned with the actual secrets file

INPUT="secrets.nix"
OUTPUT="EXAMPLE-secrets.nix"

cp "$INPUT" "$OUTPUT"

sed -i -E 's/(=\s*")[^"]*"/\1FILL_THIS_IN"/g' "$OUTPUT"

echo "generated/updated: $OUTPUT"
echo "check it looks okay before committing!"
