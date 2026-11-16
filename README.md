# Spine

Native macOS 14+ EPUB library prototype. Run with `swift run Spine` or open Package.swift in Xcode.

Choose a library folder on first launch; Spine remembers it. Change it with “Library Folder…” in the sidebar. Importing copies EPUBs into `author_name/book_name/book_name.epub` (for example, `susanna_clarke/piranesi/piranesi.epub`), leaving originals untouched. Names use lowercase snake case; missing names use `unknown_author` and `untitled`. Existing folders get a numbered suffix rather than being overwritten.

Spine scans the selected folder recursively, including existing EPUBs. Previous imports remain in ~/Library/Application Support/MinimalBooks; choose “Use Previous Library” during setup to keep using them, or import them into your new folder. Existing files and folders are not automatically reorganized, including after metadata edits. Browse covers, search, edit text metadata, open externally, and export. Authors and tags use semicolons. Saving retains a `.backup` file beside the managed book. Extracted cover caches use `.cover` files beside EPUBs.

Status: incomplete implementation of the proposed app. Cover replacement, series editing, SwiftData indexing, background processing, folder/drop import, deduplication, unsaved-change prompts and crash recovery remain unfinished. System zip/unzip are used instead of ZIPFoundation. Only import trusted local files: archive expansion and symlink defenses are not complete. Do not use as your sole library or backup.

Checks: `swift test`. Real EPUB compatibility and EPUBCheck validation remain necessary.
