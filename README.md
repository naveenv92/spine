# Spine

A native macOS EPUB library manager built with SwiftUI. Organize your book files, browse covers, edit metadata and artwork, and open books in your preferred reader.

Spine is an early prototype. Keep an independent backup of your library and import only trusted EPUB files.

## Build and run

Requires macOS 14 or later and Xcode with Swift 5.9 or later. There are no third-party package dependencies.

### Standalone app

From the repository root:

```sh
bash scripts/build-app.sh
```

Copy `.build/Spine.app` into **Applications**, then double-click it. The script builds a release binary for your Mac, bundles resources and the app icon, and applies a local ad hoc signature. It does not create a universal binary or notarize the app for distribution.

To update your installed copy, quit Spine, rerun the script, and replace the app in Applications. Building alone does not update the installed copy.

### Development

```sh
swift run Spine
```

You can also open `Package.swift` in Xcode and run the Spine target.

The standalone app and `swift run` use separate preferences. When switching between them, choose the same library folder to access the same books.

## Set up your library

Choose or create a library folder on first launch. Spine remembers it and scans its subfolders for EPUBs. Use **Library Folder…** in the sidebar to switch folders while on the library screen.

If `~/Library/Application Support/Spine` already exists, setup offers **Use Previous Library**. Spine does not create or migrate that folder automatically.

Importing copies each EPUB into your selected folder without changing the source file:

```text
Your Library/
├── Susanna Clarke/
│   ├── piranesi.epub
│   └── another-book.epub
└── .spine/
    └── Susanna Clarke/
        ├── piranesi.cover
        └── piranesi.epub.json
```

Author folders use Title Case with spaces, preserving accents, safe punctuation, and existing mixed-case spellings such as `McLean` and `O’Neill`. This changes folder names, not the author metadata inside the EPUB. Book filenames use lowercase kebab case, with accents folded and punctuation replaced by separators. Long names are shortened. Missing names use `Unknown Author` and `untitled`. For multiple authors, the first non-empty semicolon-separated author determines the folder; all authors remain in the EPUB metadata. Changing additional authors does not rename the folder, while changing the first author does. Existing filenames get a numbered suffix, such as `piranesi-2.epub`, rather than being overwritten; repeated imports create additional copies.

Spine stores cover and metadata caches in the hidden `.spine` folder, mirroring the EPUB's relative path. Finder hides dot folders by default; press **⌘⇧.** to show them. Copy the author folders when transferring books to an e-reader. The EPUB itself contains the author/title metadata and embedded cover art, so the e-reader does not need `.spine`.

Cache files appear inside `.spine` as needed:

| File | Purpose |
| --- | --- |
| `.epub` | The managed book, including its embedded cover image. |
| `.cover` | An extracted cover-image cache for thumbnails. Deleting it is safe; Spine recreates it when the library loads. |
| `.epub.json` | Cached book metadata, keyed by EPUB size and modification time. Unchanged EPUBs load without being unpacked again. Missing or invalid caches are rebuilt automatically. |

Startup scanning runs in the background with a loading indicator. The first scan builds caches; subsequent launches read cached metadata and covers for unchanged EPUBs. Imports and saves refresh their caches immediately. Changing a file’s size or modification time triggers a refresh, and deleting a cached cover regenerates it. Changes made by tools that preserve both size and modification time require deleting that book’s JSON cache to force a refresh.

Existing EPUBs are discovered where they are. Importing and saving changed author/title metadata organize files; choosing a folder does not reorganize its existing contents.

**Import New Books** accepts EPUB files, folders, or a mixture of both. Folder import searches all subfolders for `.epub` files, including uppercase extensions. Hidden files/folders, symlinks, and the current managed library are skipped. Overlapping selections are scanned once per file, and discovery completes before copying begins. A progress dialog shows scanning, the processed/total file count, and the final library refresh. This work runs in the background while the dialog prevents conflicting edits. Invalid EPUBs are reported while the remaining books continue importing. Importing the same source again still creates a numbered copy; this is not content-based deduplication.

## Use Spine

### Browse and open

Search by title or author, sort by **Title**, **Author First Name**, or **Author Last Name**, and switch between grid and list views. Author sorting uses the first listed author and supports both `First Last` and `Last, First` names. Last-name sorting treats the final word as the surname for names without a comma; compound surnames and suffixes are not inferred. Ties sort by book title. Library interactions work in both layouts:

| Interaction | Action |
| --- | --- |
| Single click | Select and highlight a book. |
| Command-click | Add or remove a book from the selection. |
| Arrow keys | Move selection through the visible books. |
| Double-click or Return | Read the active book in the system's default EPUB reader. |
| Cover's ⓘ button, toolbar ⓘ, or ⌘I | Open the book's details page. |
| Space | Open a read-only book preview; Escape closes it. |
| Right-click / Control-click | Read, view details, edit metadata, edit cover, reveal in Finder, or remove the clicked book. |

When several books are selected, keyboard actions apply to the most recently selected book; bulk editing and removal are not implemented. **Open Book** on the details page also launches the default reader; **Export** copies the EPUB to a destination you choose.

### Edit metadata

Choose **Edit Metadata** to change the title, authors, publisher, language, tags, or description. Separate multiple authors and tags with semicolons. Descriptions render HTML; enable **Edit HTML source** to change their markup.

**Save Changes** opens a confirmation dialog before writing metadata into the EPUB. Confirming overwrites the metadata without keeping a backup; it cannot be undone in Spine. Cancelling the dialog keeps your draft available for editing. If the author or title changes its normalized name, Spine also updates the author folder and EPUB filename, carries over the hidden cover cache, and removes empty old folders. Collisions use numbered filenames. Shared folders and unrelated files stay in place. **Back to Library** asks before discarding unsaved edits.

### Replace cover artwork

Choose **Edit Artwork**, select a PNG or JPEG, review the preview, then choose **Save Artwork** and confirm the replacement. Finish or cancel metadata editing first.

Spine embeds the replacement inside the EPUB and refreshes the thumbnail cache. The confirmation explains that no backup is kept and the replacement cannot be undone in Spine. Existing JPEG, PNG, and GIF covers keep their image path and format so existing cover-page references continue to work. Books without cover metadata receive a new cover image entry.

SVG cover replacement and creating a new cover page in the book's reading order are not supported.

### Remove a book

Right-click a book in the grid or list and choose **Remove book**, or choose **Remove Book** on its details page. Both require confirmation before moving files to macOS Trash.

Removal includes the EPUB, its hidden cover and metadata caches, and empty author/metadata folders. Shared folders, unrelated files, and the library root remain. A source file copied from outside the library during import is unaffected.

## Reset for debugging

Quit Spine before resetting preferences.

For the standalone app:

```sh
defaults delete com.naveenv92.Spine
```

For `swift run Spine`:

```sh
defaults delete Spine
```

These commands reset settings, including the selected library folder. They do not delete books. To test with an empty library, choose a new empty folder on the next launch.

To remove library files too, inspect your selected folder in Finder and move the files you no longer need to Trash. Older prototype builds used `~/Library/Application Support/MinimalBooks`; that folder is no longer used automatically and must be handled separately if it remains on disk.

## Tests and limitations

Run the test suite with:

```sh
swift test
```

Tests cover metadata saving, organized imports, folder renaming, duplicate names, removal, saving without backups, EPUB 2/3 cover editing, image validation, and description sizing.

Startup and imports load in the background. Saving edits still runs synchronously, though subsequent library refreshes reuse caches for unchanged books. Drag-and-drop import, automatic deduplication, series editing, and crash recovery are not implemented. Spine uses the system `zip` and `unzip` tools; archive expansion limits and archive symlink defenses remain incomplete.

Compatibility with a broader set of real EPUBs, EPUBCheck validation, and manual UI testing remain necessary. Spine does not create EPUB backups. Keep an independent copy if you need to restore earlier versions.

## License

[MIT](LICENSE)
