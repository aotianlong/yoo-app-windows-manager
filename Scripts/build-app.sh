#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
configuration=${CONFIGURATION:-debug}
app_path="$project_root/.build/YooWindowsManager.app"
contents_path="$app_path/Contents"

swift build \
    --package-path "$project_root" \
    --configuration "$configuration" \
    --product YooWindowsManager

binary_directory=$(swift build \
    --package-path "$project_root" \
    --configuration "$configuration" \
    --show-bin-path)

mkdir -p "$contents_path/MacOS"
/usr/bin/install -m 755 \
    "$binary_directory/YooWindowsManager" \
    "$contents_path/MacOS/YooWindowsManager"
/usr/bin/install -m 644 \
    "$project_root/Resources/Info.plist" \
    "$contents_path/Info.plist"

/usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    --options runtime \
    --identifier im.yoo.YooWindowsManager \
    "$app_path"

print -r -- "$app_path"
