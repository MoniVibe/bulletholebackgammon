#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'EOF'
Usage: ./build-ios.sh [options]

Options:
  --clean                         Run flutter clean first.
  --no-codesign                   Build unsigned iOS app bundle and zip it.
  --export-options-plist <path>   Path to ExportOptions.plist for signed IPA export.
  --flutter <path>                Flutter executable path (default: flutter).
  -h, --help                      Show this help.

Examples:
  ./build-ios.sh --no-codesign
  ./build-ios.sh --export-options-plist ios/ExportOptions.plist
EOF
}

clean=0
no_codesign=0
export_options_plist=""
flutter_exe="flutter"

while (($#)); do
  case "$1" in
    --clean)
      clean=1
      shift
      ;;
    --no-codesign)
      no_codesign=1
      shift
      ;;
    --export-options-plist)
      if (($# < 2)); then
        echo "Missing value for --export-options-plist" >&2
        exit 1
      fi
      export_options_plist="$2"
      shift 2
      ;;
    --flutter)
      if (($# < 2)); then
        echo "Missing value for --flutter" >&2
        exit 1
      fi
      flutter_exe="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      show_help
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS build requires macOS + Xcode. Run this script on a Mac." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

if ((clean)); then
  echo "Running flutter clean..."
  "$flutter_exe" clean
fi

echo "Running flutter pub get..."
"$flutter_exe" pub get

if ((no_codesign)); then
  echo "Building iOS app without code signing..."
  "$flutter_exe" build ios --release --no-codesign

  app_path="$repo_root/build/ios/iphoneos/Runner.app"
  zip_path="$repo_root/build/ios/iphoneos/Runner-no-codesign.zip"

  if [[ ! -d "$app_path" ]]; then
    echo "Expected app bundle not found: $app_path" >&2
    exit 1
  fi

  rm -f "$zip_path"
  if command -v ditto >/dev/null 2>&1; then
    ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
  else
    (
      cd "$repo_root/build/ios/iphoneos"
      zip -r "Runner-no-codesign.zip" "Runner.app" >/dev/null
    )
  fi

  echo ""
  echo "Unsigned iOS artifact:"
  echo "  $zip_path"
  if command -v shasum >/dev/null 2>&1; then
    echo "  sha256: $(shasum -a 256 "$zip_path" | awk '{print $1}')"
  fi
  exit 0
fi

echo "Building signed IPA..."
build_cmd=("$flutter_exe" "build" "ipa" "--release")
if [[ -n "$export_options_plist" ]]; then
  build_cmd+=("--export-options-plist=$export_options_plist")
fi
"${build_cmd[@]}"

ipa_path="$repo_root/build/ios/ipa/Runner.ipa"
echo ""
echo "Signed IPA (if signing/export succeeded):"
echo "  $ipa_path"
if [[ -f "$ipa_path" ]] && command -v shasum >/dev/null 2>&1; then
  echo "  sha256: $(shasum -a 256 "$ipa_path" | awk '{print $1}')"
fi
