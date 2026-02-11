# ZettelHub Feature Roadmap

This document outlines proposed features and enhancements to transform ZettelHub into a feature-rich Zettelkasten note-taking system. Features are organized by category and priority.

## Current Capabilities

### Implemented
- ✅ Note creation with ERB templates
- ✅ Multiple note types (note, journal, meeting)
- ✅ SQLite indexing with FTS5 full-text search infrastructure
- ✅ YAML front matter with metadata
- ✅ Template system with variable interpolation
- ✅ Configuration system (global + local)
- ✅ Shell completion
- ✅ ID generation (8-character hex)
- ✅ Tag support in metadata
- ✅ Alias generation for searchability
- ✅ Reindex command (`zh reindex`) - Recursively scans notebook directory and rebuilds SQLite index
- ✅ Search command (`zh search`) – FTS5 full-text search, filters (type, tag, date, path), interactive by default (fzf), --list/--table/--json for stdout.
- ✅ Find command (`zh find`) – Interactive find in note content (ripgrep + fzf).
- ✅ Journal commands (`zh today`, `zh yesterday`, `zh tomorrow`, `zh journal [DATE]`) – Open or create that day's journal file and open in editor; config: `journal.path_pattern`, `tools.editor.journal`; `zh journal` with no args = today.
- ✅ Default tags from templates – Templates can define `config.default_tags` in YAML front matter; merged with user-supplied tags when creating notes (note, journal, meeting templates).
- ✅ Tag commands (`zh tag list|add|remove|rename`, `zh tags`) – List tags with counts; add/remove tag on a note by ID; rename tag across all notes.
- ✅ Import command (`zh import`) – Bulk import markdown notes with new IDs, wikilink/markdown link resolution, `--into DIR`, `--recursive`, `--dry-run`; type-aware when templates exist.
- ✅ Link tracking and backlinks – Indexer extracts wikilinks and markdown links; `links` table; backlinks section in note files; `zh links NOTE_ID` (outgoing), `zh backlinks NOTE_ID` (incoming).
- ✅ Graph command (`zh graph NOTE_ID`) – Link graph for a note and its neighbourhood (DOT or ASCII format).
- ✅ Bookmark type and command – Resource/Bookmark model; `zh bookmark` (interactive browser), `zh bookmark add [URL]`, `zh bookmark export`, `zh bookmark refresh` (stale detection, meta description fetch).

### Not Yet Implemented
- List command (`zh list`) – list all notes in table/list/JSON (search/find provide interactive discovery)
- General browse command (`zh browse`) for all notes (bookmark has its own interactive browser)
- Edit, update, delete, read commands (find/search open in editor; no dedicated read/update/delete)
- Link following (`zh follow`) – interactive follow from a note
- Stats, orphans, general export (HTML/PDF/JSON); bookmark export to Netscape bookmarks.html is implemented
- Neovim/tmux integration, advanced query language

## High Priority Features

### Search & Discovery

#### 1. Search Command (`zh search`) ✅ IMPLEMENTED
- **Implemented**: FTS5 full-text search, filters (type, tag, date, path), interactive by default (fzf with preview), --list/--table/--json (or --format) to print to stdout.
- **Examples**:
  ```bash
  zh search "meeting"                    # Default: interactive (fzf)
  zh search --list "meeting"             # Print list to stdout
  zh search --format json "notes"        # JSON output
  zh search --type journal --date "2026-01"
  zh search --tag work "project"
  ```

#### 2. List Command (`zh list`) – Not yet
- **List all notes**: Display notes in table/list/JSON (no interactive fzf). Overlaps with `zh search --list/--table/--json` for filtered output; a dedicated `zh list` would provide unfiltered or default-sort listing.
- **Sorting options**: By date, title, type, modification time
- **Examples**:
  ```bash
  zh list
  zh list --type meeting --sort date
  ```

#### 3. Browse Command (`zh browse`) – Not yet
- **General-note browsing**: Interactive fzf over all notes (by tag/type/date). Overlaps with `zh search` (interactive) and `zh find`; a dedicated browse could combine navigation by tags/types/dates with preview. Note: `zh bookmark` already provides an interactive browser for bookmarks.
- **Examples**:
  ```bash
  zh browse
  zh browse --tag work
  ```

### Link Management

#### 4. Link Tracking, Backlinks & Graph ✅ IMPLEMENTED
- ✅ Link extraction (wikilinks and markdown), `links` table, backlinks section in notes; `zh links`, `zh backlinks`, `zh graph` (DOT/ASCII). See Current Capabilities.
- **Future**: `zh follow`; graph filters (e.g. `--tag`, `--format mermaid`).

#### 5. Link Following (`zh follow`) – Not yet
- **Follow links**: Open linked notes from current note
- **Interactive link selection**: Use fzf to choose which link to follow
- **Link creation**: Helper to create links while editing
- **Link syntax**: Support both `[[id]]` and `[[title]]` formats
- **Examples**:
  ```bash
  zh follow NOTE_ID           # Show links, let user choose
  zh follow --create LINK_ID  # Create link in current note
  ```

### Note Management

#### 6. Edit Command (`zh edit`)
- **Open note in editor**: Default to `$EDITOR` or Neovim
- **Note selection**: Use fzf to select note to edit
- **Auto-reindex**: Re-index note after editing
- **Link to note ID**: `zh edit NOTE_ID`
- **Link to note title**: `zh edit "Note Title"`
- **Examples**:
  ```bash
  zh edit                      # Interactive selection with fzf
  zh edit abc12345            # Edit by ID
  zh edit "Meeting Notes"     # Edit by title (fuzzy match)
  ```

#### 7. Update Command (`zh update`)
- **Update metadata**: Modify title, tags, type without full edit
- **Bulk updates**: Update multiple notes
- **Examples**:
  ```bash
  zh update abc12345 --title "New Title"
  zh update abc12345 --add-tag work
  zh update --tag old-tag --add-tag new-tag  # Bulk tag update
  ```

#### 8. Delete Command (`zh delete`)
- **Delete notes**: Remove note file and database entry
- **Safety checks**: Confirm deletion, check for backlinks
- **Orphan detection**: Warn if deleting creates orphaned links
- **Examples**:
  ```bash
  zh delete abc12345
  zh delete --interactive     # Select with fzf
  ```

#### 9. Reindex Command (`zh reindex`) ✅ IMPLEMENTED
- ✅ Recursively scans notebook for `.md` files, rebuilds SQLite index; `zh add` auto-indexes new notes; error handling and progress feedback; second pass updates links and backlinks sections; help and completion.
- **Future**: Incremental reindex (mtime), `--all` flag, re-index single note by ID.
- **Examples**:
  ```bash
  zh reindex
  zh reindex --help
  ```

### Tag Management

#### 10. Tag Commands ✅ IMPLEMENTED
- ✅ **`zh tags`** (same as `zh tag list`): List all tags with counts
- ✅ **`zh tag add TAG NOTE_ID`**: Add tag to note
- ✅ **`zh tag remove TAG NOTE_ID`**: Remove tag from note
- ✅ **`zh tag rename OLD_TAG NEW_TAG`**: Rename tag across all notes
- **Not yet**: Tag autocomplete for fzf, tag co-occurrence statistics
- **Examples**:
  ```bash
  zh tags                      # List all tags
  zh tag add work abc12345
  zh tag rename old-tag new-tag
  ```

## Medium Priority Features

### Reading & Preview

#### 11. Read Command (`zh read`)
- **Display note**: Show formatted note content
- **Preview integration**: Use `glow` for beautiful markdown rendering
- **Fallback to bat**: If glow not available, use bat for syntax highlighting
- **Options**:
  - `--raw`: Show raw markdown
  - `--html`: Render to HTML
  - `--pdf`: Export to PDF (via pandoc)
- **Examples**:
  ```bash
  zh read abc12345             # Pretty print with glow
  zh read --interactive        # Select with fzf, preview with glow
  ```

#### 12. Daily Notes Enhancement ✅ PARTIALLY IMPLEMENTED
- ✅ **`zh today`**: Open/create today's journal entry
- ✅ **`zh yesterday`**: Open yesterday's journal
- ✅ **`zh tomorrow`**: Open/create tomorrow's journal entry
- ✅ **`zh journal [DATE]`**: Open journal for specific date (no args = today)
- **Calendar view**: Show which dates have journal entries (not yet implemented)
- **Integration**: Link daily notes to meeting notes, regular notes (not yet implemented)

### Statistics & Analytics

#### 13. Stats Command (`zh stats`)
- **Note counts**: Total notes, by type, by tag
- **Date ranges**: Notes created/modified in time periods
- **Link statistics**: Most linked notes, orphaned notes
- **Tag statistics**: Most used tags, tag frequency
- **Growth trends**: Notes over time
- **Examples**:
  ```bash
  zh stats
  zh stats --type journal
  zh stats --tag work
  ```

#### 14. Orphan Detection (`zh orphans`)
- **Find orphaned notes**: Notes with no incoming links
- **Find broken links**: Links pointing to non-existent notes
- **Fix broken links**: Interactive tool to fix or remove broken links
- **Examples**:
  ```bash
  zh orphans                   # List orphaned notes
  zh orphans --fix             # Interactive fix
  ```

### Export & Integration

#### 15. Export Command (`zh export`) – Not yet
- **General export**: Markdown, HTML, PDF, JSON by type/tag/date. Note: `zh bookmark export` exists (Netscape bookmarks.html).
- **Examples** (future):
  ```bash
  zh export --format html --tag work
  zh export --format pdf --type journal --date "2026-01"
  ```

#### 16. Import Command (`zh import`) ✅ IMPLEMENTED
- ✅ **Bulk import**: Import markdown files with front matter
- ✅ **New IDs**: Assign new IDs to imported notes
- ✅ **Link resolution**: Resolve `[[wikilinks]]` and markdown `[text](path)` to new IDs/paths
- ✅ **Options**: `--into DIR`, `--recursive`, `--dry-run`; type-aware when templates match
- **Examples**:
  ```bash
  zh import /path/to/notes/*.md
  zh import --recursive /path/to/notes
  zh import --dry-run --into imported /path/to/notes
  ```

## Neovim Integration Features

### Editor Integration

#### 17. Neovim Plugin Support
- **LSP integration**: Language Server Protocol for ZettelHub
- **Commands in Neovim**:
  - `:ZkNew` - Create new note
  - `:ZkSearch` - Search notes (opens fzf in Neovim)
  - `:ZkLink` - Insert link to note
  - `:ZkBacklinks` - Show backlinks in current note
  - `:ZkFollow` - Follow link under cursor
- **Fuzzy finder integration**: Telescope.nvim, fzf.vim support
- **Link following**: `gf` to follow `[[links]]`
- **Auto-completion**: Note ID and title completion
- **Syntax highlighting**: Markdown with ZettelHub link syntax

#### 18. Neovim-Specific Features
- **Quick note creation**: `:ZkQuickNote` - Create note from visual selection
- **Link insertion**: `:ZkLinkInsert` - Interactive link creation with fzf
- **Daily note**: `:ZkToday` - Open today's journal
- **Note navigation**: `:ZkBrowse` - Browse notes in Neovim
- **Preview**: `:ZkPreview` - Preview note in split window with glow/bat
- **Backlink display**: Show backlinks in location list or quickfix

### Link Syntax Support

#### 19. Markdown Link Extensions
- ✅ **Implemented**: Wikilink `[[id]]` / `[[title]]` and markdown links; resolution to note IDs; link extraction and storage in indexer; backlinks section in notes.
- **Future**: Link display as title in rendered markdown; broken-link highlighting in editor; auto-create note on link target missing.

## Advanced Features

### Query & Filtering

#### 20. Advanced Query Language
- **Query syntax**: SQL-like or natural language queries
- **Complex filters**: Combine type, tag, date, content filters
- **Saved queries**: Save and reuse common queries
- **Query examples**:
  ```bash
  zh query "type:meeting AND tag:work AND date:2026-01"
  zh query "title:meeting OR body:discussion"
  ```

#### 21. Smart Suggestions
- **Related notes**: Suggest notes based on content similarity
- **Tag suggestions**: Suggest tags based on content
- **Link suggestions**: Suggest notes to link to
- **Completion suggestions**: Based on existing notes

### Visualization

#### 22. Graph Visualization ✅ PARTIALLY IMPLEMENTED
- ✅ **Implemented**: `zh graph NOTE_ID` – link graph for a note and its neighbourhood (DOT or ASCII). See Current Capabilities and Link Management (4).
- **Future**: Full notebook graph; `--tag` / `--format mermaid`; HTML interactive graph; graphviz/mermaid-cli integration.

#### 23. Timeline View
- **Chronological view**: Notes organized by date
- **Calendar integration**: Show notes on calendar
- **Journal timeline**: Visual timeline of journal entries

### Workflow Enhancements

#### 24. Templates Enhancement
- ✅ **Template variables**: Built-in variables already include date, year, month, week, week_year, month_name, month_name_short, day_name, day_name_short, time, timestamp, id, etc.
- **Future**: Template inheritance (base + overrides), reusable snippets, fzf-based template picker.

#### 25. Note Types Enhancement
- ✅ **Resource/Bookmark**: Implemented – bookmark type, `zh bookmark` (browser, add, export, refresh).
- **Meeting notes**: Auto-extract attendees, action items (future)
- **Journal entries**: Daily/weekly/monthly views (daily via `zh today`/journal; weekly/monthly views future)
- **Guide templates**: Additional resource subtypes (future)
- **Contact notes**: People management (future)
- **Task notes**: Task tracking with due dates (future)

#### 26. Batch Operations
- ✅ **Partial**: `zh tag rename OLD NEW` renames a tag across all notes (bulk). Bulk add/remove tag across multiple notes not yet.
- **Future**: Bulk move, bulk rename by pattern, bulk export.

### Performance & Optimization


## Tool Integration Enhancements

### fzf Integration

#### 27. Enhanced fzf Integration
- **Multi-select**: Select multiple notes for batch operations

### bat Integration

#### 28. bat Preview Features
- **Custom highlighting**: Highlight links, tags, metadata

### tmux Integration

#### 29. tmux Workflow Integration
- **Session / layout scripts**: Script or `zh tmux` to launch a dedicated tmux session with a ZettelHub layout (e.g. pane 1: `zh search --interactive` or browse, pane 2: editor, optional pane 3: `zh read` or glow preview).
- **Key bindings**: Document suggested tmux key bindings (e.g. prefix+z for zh search in new pane, prefix+n for new note) for `~/.tmux.conf`.
- **Status line**: Optional status integration to show current notebook or last-opened note in tmux status (e.g. script or variable for status-right).
- **Send-keys / scripting**: Document or support sending a selected note path/ID to a tmux pane (e.g. open note in target pane) for scripted and key-bound workflows.
- **Copy mode**: Document using tmux copy mode with `zh list` or `zh search` output to copy note IDs or paths.
- **Detach / reattach**: Document workflow for detaching from a zk session and reattaching to the same layout (browser, editor, preview).

## Configuration Enhancements

#### 30. Editor Configuration
- **Editor integration**: Auto-detect and configure editor integration

#### 31. Tool Configuration
- **Fallback tools**: Configure fallback if tools not available

#### 32. Link Configuration
- **Link syntax**: Configure link syntax (`[[...]]`, `[...](...)`, etc.)
- **Link resolution**: Configure how links are resolved
- **Auto-link**: Auto-create links on note creation

## Documentation & Help

#### 33. Enhanced Help System
- **Tutorials**: Built-in tutorials for common workflows
- **Man pages**: Generate man pages from help text

#### 34. Interactive Tutorial
- **Onboarding**: Interactive tutorial for new users
- **Workflow guides**: Guided workflows for common tasks
- **Best practices**: Tips and best practices

## Future Considerations

### Collaboration Features
- **Sync**: Sync notes across devices (future)
- **Version control**: Git integration for note history

### AI/ML Features
- **Content suggestions**: AI-powered content suggestions
- **Auto-tagging**: Automatic tag suggestions
- **Related notes**: ML-based related note discovery
- **Summarization**: Auto-summarize notes

## Implementation Priority

### Phase 1: Core Functionality (High Priority)
1. ✅ Search command with fzf integration
2. List/browse commands (not yet; search/find provide discovery)
3. Edit command (not yet)
4. ✅ Link tracking, backlinks, and graph (`zh links`, `zh backlinks`, `zh graph`)
5. Read command with glow/bat (not yet)

### Phase 2: Note Management (High Priority)
6. Update command (not yet)
7. Delete command (not yet)
8. ✅ Reindex command
9. ✅ Tag management (`zh tag`, `zh tags`)
10. ✅ Daily notes (`zh today`, `zh yesterday`, `zh tomorrow`, `zh journal`)
11. ✅ Bookmark type and command (`zh bookmark` browser, add, export, refresh)

### Phase 3: Neovim Integration (Medium Priority)
12. Neovim plugin/LSP
13. Link following in editor (`zh follow`)
14. Quick note creation, backlink display

### Phase 4: Advanced Features (Medium Priority)
15. Statistics and analytics (`zh stats`)
16. Orphan detection (`zh orphans`)
17. ✅ Graph (neighbourhood DOT/ASCII; future: full graph, mermaid)
18. ✅ Import; general export not yet (bookmark export implemented)

### Phase 5: Polish & Optimization (Lower Priority)
19. Performance optimization
20. Enhanced tool integration (fzf multi-select, bat custom highlighting)
21. Advanced query language
22. Documentation improvements
23. tmux session/layout and key-binding documentation (or optional `zh tmux` script)

## Notes

- All new commands should follow existing patterns (Ruby classes in `lib/cmd/`)
- Commands should implement `--completion` for shell completion
- Commands should support `--help` flag
- All commands should have comprehensive tests
- Consider backward compatibility when adding features
- Follow existing code style and architecture patterns
- Document all new features in README and ARCHITECTURE.md
