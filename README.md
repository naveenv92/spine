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
└── susanna_clarke/
    └── piranesi/
        ├── piranesi.epub
        ├── piranesi.cover
        └── piranesi.epub.backup
```

Folder and file names use lowercase snake case derived from the EPUB's author and title metadata. Accents are folded, punctuation becomes separators, and long names are shortened. Missing names use `unknown_author` and `untitled`. Multiple authors are combined into one author folder name. Existing book folders get a numbered suffix, such as `piranesi_2`, rather than being overwritten; repeated imports create additional copies.

The `.cover` and `.backup` files appear as needed:

| File | Purpose |
| --- | --- |
| `.epub` | The managed book, including its embedded cover image. |
| `.cover` | An extracted cover-image cache for thumbnails. Deleting it is safe; Spine recreates it when the library loads. |
| `.epub.backup` | The EPUB before its most recent metadata or artwork save. This is one previous version, not a complete history. |

Existing EPUBs are discovered where they are. Importing and saving changed author/title metadata organize files; choosing a folder does not reorganize its existing contents.

## Use Spine

### Browse and open

Search by title or author, sort by either field, and switch between grid and list views. Click a book to open its details page. **Open Book** launches the EPUB in its default external reader; **Export** copies it to a destination you choose.

### Edit metadata

Choose **Edit Metadata** to change the title, authors, publisher, language, tags, or description. Separate multiple authors and tags with semicolons. Descriptions render HTML; enable **Edit HTML source** to change their markup.

**Save Changes** writes the metadata into the EPUB and keeps a pre-edit backup. If the author or title changes its normalized name, Spine also updates the folders and EPUB filename, carries over the cover cache, and removes empty old folders. Collisions use numbered folders. Shared folders and unrelated files stay in place. **Back to Library** asks before discarding unsaved edits.

### Replace cover artwork

Choose **Edit Artwork**, select a PNG or JPEG, review the preview, then choose **Save Artwork**. Finish or cancel metadata editing first.

Spine embeds the replacement inside the EPUB, retains a pre-edit backup, and refreshes the thumbnail cache. Existing JPEG, PNG, and GIF covers keep their image path and format so existing cover-page references continue to work. Books without cover metadata receive a new cover image entry.

SVG cover replacement and creating a new cover page in the book's reading order are not supported.

### Remove a book

Right-click a book in the grid or list and choose **Remove book**, or choose **Remove Book** on its details page. Both require confirmation before moving files to macOS Trash.

Removal includes the EPUB, cover cache, backup, and empty book/author folders. Shared folders, unrelated files, and the library root remain. A source file copied from outside the library during import is unaffected.

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

Tests cover metadata saving, organized imports, folder renaming, duplicate names, removal, backups, EPUB 2/3 cover editing, image validation, and description sizing.

Library scanning and EPUB processing run synchronously, so large libraries may pause the interface. Folder/drop import, automatic deduplication, series editing, and crash recovery are not implemented. Spine uses the system `zip` and `unzip` tools; archive expansion limits and archive symlink defenses remain incomplete.

Compatibility with a broader set of real EPUBs, EPUBCheck validation, and manual UI testing remain necessary. Use an independent backup rather than relying only on the single pre-edit `.backup` file.

## License

[MIT](LICENSE)
