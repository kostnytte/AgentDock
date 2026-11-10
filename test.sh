#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/module-cache
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Models.swift Tests/StorageTests.swift -o build/StorageTests
build/StorageTests
swiftc -swift-version 5 -module-cache-path build/module-cache -framework AppKit -framework SwiftUI -framework ApplicationServices \
    Sources/Models.swift Sources/ShortcutModels.swift Sources/ShortcutSupport.swift Sources/ShortcutStore.swift Sources/WindowAccess.swift Sources/BoardStore.swift Sources/WorkflowStore.swift Tests/BoardTests.swift -o build/BoardTests
build/BoardTests
swiftc -swift-version 5 -module-cache-path build/module-cache -framework AppKit -framework SwiftUI -framework ApplicationServices \
    Sources/Models.swift Sources/ShortcutModels.swift Sources/ShortcutSupport.swift Sources/ShortcutStore.swift Sources/WindowAccess.swift Sources/BoardStore.swift Sources/WorkflowStore.swift Tests/WorkflowTests.swift -o build/WorkflowTests
build/WorkflowTests
swiftc -swift-version 5 -module-cache-path build/module-cache -framework AppKit -framework SwiftUI -framework ApplicationServices \
    Sources/Models.swift Sources/ShortcutModels.swift Sources/ShortcutSupport.swift Sources/ShortcutStore.swift Sources/WindowAccess.swift Sources/BoardStore.swift Sources/WorkflowStore.swift Tests/ShortcutTests.swift -o build/ShortcutTests
build/ShortcutTests
