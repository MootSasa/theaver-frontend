#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PRIV_KEY_FILE="${LINUX_GPG_PRIVATE_KEY_FILE:-$FRONTEND_DIR/signing/linux/theaver-release-private.asc}"
ENV_FILE="$FRONTEND_DIR/signing/linux/gpg-signing.env"

if [ -z "${LINUX_GPG_PASSPHRASE:-}" ] && [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

GNUPGHOME_TMP="$(mktemp -d)"
chmod 700 "$GNUPGHOME_TMP"
trap 'rm -rf "$GNUPGHOME_TMP"' EXIT

cat > "$GNUPGHOME_TMP/gpg.conf" <<EOF
pinentry-mode loopback
EOF

if [ -n "${LINUX_GPG_PRIVATE_KEY_BASE64:-}" ]; then
  echo "$LINUX_GPG_PRIVATE_KEY_BASE64" | tr -d ' \n\r' | base64 -d > "$GNUPGHOME_TMP/private.asc"
  PRIV_KEY_FILE="$GNUPGHOME_TMP/private.asc"
fi

HAS_GPG_KEY=0
if [ -f "$PRIV_KEY_FILE" ] && [ -n "${LINUX_GPG_PASSPHRASE:-}" ]; then
  gpg --homedir "$GNUPGHOME_TMP" --batch --pinentry-mode loopback \
    --passphrase "$LINUX_GPG_PASSPHRASE" --import "$PRIV_KEY_FILE" >/dev/null 2>&1 && HAS_GPG_KEY=1 || true
fi

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
  if [ -d "$FRONTEND_DIR/dist/linux" ]; then
    while IFS= read -r -d '' f; do
      TARGETS+=("$f")
    done < <(find "$FRONTEND_DIR/dist/linux" -maxdepth 1 -type f -name "*.tar.gz" -print0)
  fi
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "No Linux archives specified or found in dist/linux."
  exit 0
fi

for ARCHIVE in "${TARGETS[@]}"; do
  [ -f "$ARCHIVE" ] || continue
  DIR="$(dirname "$ARCHIVE")"
  BASE="$(basename "$ARCHIVE")"
  (
    cd "$DIR"
    sha256sum "$BASE" > "${BASE}.sha256"
    echo "✅ Generated SHA-256 checksum: ${BASE}.sha256"
    if [ "$HAS_GPG_KEY" -eq 1 ]; then
      rm -f "${BASE}.asc" "${BASE}.sha256.asc"
      gpg --homedir "$GNUPGHOME_TMP" --batch --yes --pinentry-mode loopback \
        --passphrase "$LINUX_GPG_PASSPHRASE" \
        --detach-sign --armor -o "${BASE}.asc" "$BASE"
      gpg --homedir "$GNUPGHOME_TMP" --batch --yes --pinentry-mode loopback \
        --passphrase "$LINUX_GPG_PASSPHRASE" \
        --detach-sign --armor -o "${BASE}.sha256.asc" "${BASE}.sha256"
      echo "✅ Signed Linux archive with GPG: ${BASE}.asc"
    else
      echo "ℹ️ GPG private key not configured; created ${BASE}.sha256 only."
    fi
  )
done
