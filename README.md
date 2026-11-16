# Spine

Native macOS 14+ EPUB library prototype. Run with `swift run Spine` or open Package.swift in Xcode.

Imports copies into ~/Library/Application Support/MinimalBooks. Browse covers, search, edit text metadata, open externally, and export. Authors and tags use semicolons. Saving retains a `.backup` file beside the managed book.

Status: incomplete implementation of the proposed app. Cover replacement, series editing, SwiftData indexing, background processing, folder/drop import, deduplication, unsaved-change prompts and crash recovery remain unfinished. System zip/unzip are used instead of ZIPFoundation. Only import trusted local files: archive expansion and symlink defenses are not complete. Do not use as your sole library or backup.

Checks: `swift test`. Real EPUB compatibility and EPUBCheck validation remain necessary.
