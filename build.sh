#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
build_output="${1:-build}"
mkdir -p "$build_output" build/module-cache
app_stage="$(mktemp -d "$build_output/.stage.XXXXXX")"
trap 'rm -rf "$app_stage"' EXIT
app_bundle="$app_stage/AgentDock.app"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 \
    -module-cache-path build/module-cache \
    -framework AppKit -framework SwiftUI -framework ApplicationServices -framework Carbon \
    Sources/Models.swift Sources/ShortcutModels.swift Sources/ShortcutSupport.swift Sources/ShortcutStore.swift Sources/ShortcutViews.swift Sources/ShortcutPanels.swift Sources/WindowAccess.swift Sources/BoardStore.swift Sources/WorkflowStore.swift Sources/WorkflowViews.swift Sources/WorkflowPanels.swift Sources/Views.swift Sources/FolderViews.swift Sources/WindowCardDrag.swift Sources/WindowSwitcherView.swift Sources/WindowPinShortcut.swift Sources/WindowPinTracker.swift Sources/main.swift \
    -o "$app_bundle/Contents/MacOS/AgentDock"
cp Info.plist "$app_bundle/Contents/Info.plist"
swiftc -module-cache-path build/module-cache -framework AppKit Icon.swift -o build/CreateIcon
build/CreateIcon build/AgentDock.iconset "$app_bundle/Contents/Resources/AgentDock.icns"
signing_identity="${AGENTDOCK_SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
    codesign --force --sign - --options runtime --identifier no.magne.agentdock "$app_bundle"
else
    codesign --force --sign "$signing_identity" --options runtime --timestamp \
        --identifier no.magne.agentdock "$app_bundle"
fi
codesign --verify --strict "$app_bundle"
if [[ -d "$build_output/AgentDock.app" ]]; then mv "$build_output/AgentDock.app" "$app_stage/previous.app"; fi
mv "$app_bundle" "$build_output/AgentDock.app"
print "Ferdig: ${PWD}/${build_output}/AgentDock.app"
