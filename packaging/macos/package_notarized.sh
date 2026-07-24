#!/usr/bin/env bash
set -euo pipefail

# 使用方法：package_notarized.sh <app_path> <version> <artifact_dir>
app_path="${1:?缺少 .app 路径}"
release_version="${2:?缺少发布版本}"
artifact_dir="${3:?缺少产物目录}"

# 标签发布必须具备全部签名与公证凭据，不能静默回退到未签名产物。
required_env=(
  APPLE_CERTIFICATE_BASE64
  APPLE_CERTIFICATE_PASSWORD
  APPLE_SIGNING_IDENTITY
  APPLE_API_KEY_BASE64
  APPLE_API_KEY_ID
  APPLE_API_ISSUER_ID
)
for name in "${required_env[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "缺少 macOS 签名或公证凭据：$name" >&2
    exit 1
  fi
done

runner_temp="${RUNNER_TEMP:-$(mktemp -d)}"
certificate_path="$runner_temp/local-tag-player-developer-id.p12"
api_key_path="$runner_temp/AuthKey_${APPLE_API_KEY_ID}.p8"
keychain_path="$runner_temp/local-tag-player-signing.keychain-db"
keychain_password="$(uuidgen)"
staging_dir="$runner_temp/local-tag-player-dmg"
dmg_path="$artifact_dir/LocalTagPlayer-$release_version-macos.dmg"
original_keychains=()

# 保存签名前的用户 keychain 搜索顺序，保证脚本在本地执行后不会改变开发机环境。
while IFS= read -r keychain_line; do
  keychain_line="${keychain_line#*\"}"
  keychain_line="${keychain_line%\"*}"
  if [[ -n "$keychain_line" ]]; then
    original_keychains+=("$keychain_line")
  fi
done < <(security list-keychains -d user)

cleanup() {
  if (( ${#original_keychains[@]} > 0 )); then
    security list-keychains -d user -s "${original_keychains[@]}" >/dev/null 2>&1 || true
  fi
  security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
  rm -f "$certificate_path" "$api_key_path"
  rm -rf "$staging_dir"
}
trap cleanup EXIT

mkdir -p "$artifact_dir"
rm -rf "$staging_dir"
mkdir -p "$staging_dir"

# OpenSSL 在 GitHub macOS runner 上稳定支持单行 Base64，避免 BSD/GNU base64 参数差异。
printf '%s' "$APPLE_CERTIFICATE_BASE64" | openssl base64 -d -A -out "$certificate_path"
printf '%s' "$APPLE_API_KEY_BASE64" | openssl base64 -d -A -out "$api_key_path"
chmod 600 "$certificate_path" "$api_key_path"

security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$certificate_path" \
  -k "$keychain_path" \
  -P "$APPLE_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$keychain_password" \
  "$keychain_path"
security list-keychains -d user -s "$keychain_path"

# Flutter bundle 含嵌套 framework 与 dylib；从最外层以 hardened runtime 重新签名并严格验证。
codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "$APPLE_SIGNING_IDENTITY" \
  --entitlements macos/Runner/Release.entitlements \
  "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

ditto "$app_path" "$staging_dir/Local Tag Player.app"
ln -s /Applications "$staging_dir/Applications"
hdiutil create \
  -volname 'Local Tag Player' \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

# DMG 也签名并提交 Apple 公证，成功后把票据 staple 到最终分发文件。
codesign --force --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$dmg_path"
codesign --verify --strict --verbose=2 "$dmg_path"
xcrun notarytool submit "$dmg_path" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --key-id "$APPLE_API_KEY_ID" \
  --key "$api_key_path" \
  --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"
