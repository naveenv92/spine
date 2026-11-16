# Spine

Native macOS 14+ EPUB library prototype. Run with `swift run Spine` or open Package.swift in Xcode.

Choose a library folder on first launch; Spine remembers it. Change it with “Library Folder…” in the sidebar. Importing copies EPUBs into `author_name/book_name/book_name.epub` (for example, `susanna_clarke/piranesi/piranesi.epub`), leaving originals untouched. Names use lowercase snake case; missing names use `unknown_author` and `untitled`. Existing folders get a numbered suffix rather than being overwritten.

Spine scans the selected folder recursively, including existing EPUBs. The built-in library location is ~/Library/Application Support/Spine; if it exists, choose “Use Previous Library” during setup to use it. Saving a changed author or title also updates the book's folders and filename, moving its cover cache and retaining a pre-edit `.backup`. Name collisions use numbered folders. Other existing files are not automatically reorganized. Browse covers, search, edit text metadata, open externally, and export. Authors and tags use semicolons. Extracted cover caches use `.cover` files beside EPUBs.

To remove a book, right-click its card or list row and choose “Remove book”, or use “Remove Book” on its details page. After confirmation, Spine moves the EPUB, cover cache, backup, and empty book/author folders to Trash. Shared folders, unrelated files, and the library root stay in place.

Use “Edit Artwork” on the details page to choose a PNG/JPEG, preview it, and save it inside the EPUB. Existing JPEG, PNG, and GIF covers retain their image path and format; books without cover metadata receive a new cover image. A pre-edit backup is kept and the cover cache refreshes. SVG cover replacement and adding a new cover reading page are not supported. Finish or cancel metadata editing before editing artwork.

Status: incomplete implementation of the proposed app. Series editing, SwiftData indexing, background processing, folder/drop import, deduplication, and crash recovery remain unfinished. System zip/unzip are used instead of ZIPFoundation. Only import trusted local files: archive expansion and symlink defenses are not complete. Do not use as your sole library or backup.

Checks: `swift test`. Real EPUB compatibility and EPUBCheck validation remain necessary.
