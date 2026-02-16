# ZettelHub

A command-line Zettelkasten and PIM.

## Introduction

> [!NOTE] 
> The author started this project as an exercise to learn the Ruby
> programming language, and the core of the project was developed in a
> _traditional_ manner, the need and urgency to have a working tool, combined
> with curiosity and professional interest quickly morphed this project into
> being **heavily** co-developed with the aid of A.I. code-assistants. 

ZettelHub started it's life as a collection of `bash` scripts to manage a 
personal notes collection. The author wanted something that was aligned to the
[Zettelkasten](https://zettelkasten.de/) principles, but was a bit more
automated. It turns out that `bash` is not really the _language_ to use for
templating. The author also tried other tools like [Obsidian](https://obsidian.md) 
and [zk-org](https://zk-org.github.io), but these were too rigid or not
structured enough for their workflow.

A large part of their *notes* collection or rather *personal knowledge base*
contained information that would be better managed using a Personal Information
Management (PIM) tool (anyone remember [Lotus
Organizer](https://en.wikipedia.org/wiki/IBM_Lotus_Organizer)?), but would
benefit from the tagging and linking concepts in a Zettelkasten.

ZettelHub is not meant to enforce Zettelkasten principles, but rather acts as a
glorified template engine that can help you manage tags, id's and a consistent
outer structure for your knowledge system. The author's workflow necessitates
keeping track of information regarding people, customers and products as well,
which don't fit into a traditional Zettelkasten management paradigm easily, but
should still maintain some sort of relationship. Again this tool has been
developed to align to the author's needs, and not a generic personal knowledge
base management tool. Perhaps other people might find it useful.

Some of the design criteria for ZettelHub includes:

- Don't get in the way! Present as little friction as possible when a note needs
  creating quickly.
- All notes/content are Markdown files.
- Semantic meaning and metadata lives in YAML frontmatter in the Markdown file.
- The search index can be rebuilt from the on disk files at any time.
- Notes/content can be placed under Git version control.
- The template system helps to manage *types* of content - i.e. journals,
  meetings, notes, etc.
- The modules and templates should work together to automate as much of the
  repetitive aspects of building a knowledge base as possible. In other words
  assign often used tags, a note id, a date etc. using the template system so
  that you can spend more time creating the content rather than curating it.
- Being pure Markdown, links between notes should be Markdown. Support might be
  attempted for the popular _\[\[WikiLinks\]\]_ format, but it's not in the
  Markdown spec. 
- Use your weapon of choice when it comes to an editor.
- Things change. File names change, when they do, links break. The indexing
  engine tries to resolve those broken links when it can.
- Be extensible.

## Requirements

- **Ruby**: Ruby 3.0 or later.
- **Runtime Ruby gems**: `sqlite3`, `commonmarker`; `nokogiri` is optional (used for bookmark meta description fetch when installed).
- **Runtime external tools**:
  - **Required** for interactive find/search: [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`), [fzf](https://github.com/junegunn/fzf).
  - **Optional** (configurable in `config.yaml`; fallbacks exist where noted): [bat](https://github.com/sharkdp/bat) (preview; fallback `cat`), [glow](https://github.com/charmbracelet/glow) (reader), `open` (macOS) / `xdg-open` (Linux), and an editor (e.g. vim; or set `EDITOR`).
- **Development**: Ruby gems `minitest`, `rubocop`; external tools [bats](https://github.com/bats-core/bats-core) (shell tests), [shellcheck](https://www.shellcheck.net/) (bash lint for `bin/zh`).


| Tool       | Tested version |
| ---------- | -------------------------------- |
| bat        | 0.26.0                           |
| fzf        | 0.66.1                           |
| rg (ripgrep) | 15.1.0                         |
| glow       | 2.1.1                            |
| bats       | 1.12.0                           |
| shellcheck | 0.11.0                           |

## Overview

`ZettelHub` is a collection of CLI tools to manage a `Zettelkasten` style note
management system. All notes are created using the CommonMark Markdown Ruby gem.
Notes can have YAML front matter to provide metadata.

The primary function of `ZettelHub` is to provide a templating system for
creating notes of different types. Users can create different types of notes
using templates. The bundled templates include:

- A daily journal type
- A meeting type
- A general note type

`ZettelHub` is configured using a YAML configuration file named `config.yaml`
stored in a directory named `ZettelHub` under the default XDG configuration
directory, `$HOME/.config`.

The configuration contains the path to the user's default Zettel notebook store,
and the names of the default templates available. Template files are searched in
two locations (in order):
1. Local templates: `.zh/templates/` (within the notebook directory)
2. Global templates: `$HOME/.config/zh/templates/`

This allows notebook-specific templates to override global defaults.

### Data Model

Provisional data model for organising notes:

Base Type: Document
Attributes: - id: - title: - type: - path: - date:

- Document Types:
  - **Note**: Base note class (extends Document)
  - **Journal**: Journal entry class (extends Note)
  - **Meeting**: Meeting notes class (extends Note)
  - **Resource** (extends Document)
    - Bookmark : (extends Resource)

### Template files

Template files are developed using Embedded Ruby (ERB), allowing for
placeholders to be replaced in the YAML front matter, and the body of the note.

**YAML Quoting Requirements:**

When writing ERB templates, it's important to properly quote YAML values to
avoid parsing errors:

1. **String values must be quoted** if they may contain special YAML characters
   (`:`, `#`, `[`, `]`, etc.): 

   ```yaml 
   title: "<%= title %>" 
   date: "<%= date %>"
   aliases: "<%= aliases %>" 
   ```

2. **The `config.path` field must always be quoted** since it may contain
   special characters from interpolated variables: 

   ```yaml 
   config: 
    path: "<%= id %>-<%= title %>.md" 
   ```

3. **The `tags` field should NOT be quoted** since it's rendered as an inline
   YAML array: 

   ```yaml 
   tags: <%= tags %> 
   ``` 

   The `tags` variable is
   automatically formatted as `["tag1", "tag2"]` by the add command.

**Filename Normalization with `slugify`:**

Templates can use the `slugify` function to normalize strings for use in
filenames. The `slugify` function:
- Converts text to lowercase
- Replaces spaces and special characters with the configured replacement
  character (default: `-` hyphen)
- Collapses multiple consecutive replacement characters
- Removes leading/trailing replacement characters
- Preserves hyphens and existing underscores

The replacement character can be configured in `config.yaml`: 

```yaml
slugify_replacement: '-'  # Options: '-', '_', or '' (empty string to remove)
```

Example usage in `config.path`: 

```yaml 
config: path: "<%= slugify(id) %>-<%= slugify(title) %>.md" 
```

This ensures filenames are filesystem-friendly and URL-safe, even when titles
contain special characters like colons, hashes, or spaces.

**Date Format Configuration:**

The date format used in templates can be configured using Ruby's `strftime`
format: 

```yaml 
date_format: '%Y-%m-%d'  # Default: ISO 8601 format 
```

This affects the `date` variable available in templates. Common formats:
- `'%Y-%m-%d'` - ISO 8601 (2024-01-15) - default
- `'%m/%d/%Y'` - US format (01/15/2024)
- `'%d-%m-%Y'` - European format (15-01-2024)

**Alias Pattern Configuration:**

Aliases are automatically generated for each note using a configurable pattern.
This is useful for searching with tools like `fzf` or `grep`:

```yaml
default_alias: '{type}> {date}: {title}'  # Default format 
```

The pattern supports variable interpolation using `{variable}` syntax:
- `{type}` - Note type (e.g., "note", "journal", "meeting")
- `{date}` - Formatted date (uses `date_format` configuration)
- `{title}` - Note title
- `{year}` - 4-digit year
- `{month}` - 2-digit month
- `{id}` - Note ID (8-character hexadecimal)

Example: 

With default pattern `'{type}> {date}: {title}'`, a note created on
2024-01-15 with title "Meeting Notes" would have alias: `"note> 2024-01-15:
Meeting Notes"`

This makes it easy to search for notes using tools like:
- `grep "note>" *.md` - Find all notes
- `fzf` - Interactive search with default alias pattern

Templates can include a special `config` attribute in the front matter to
override the default filename pattern. The `config.path` attribute specifies a
custom filepath pattern that will be used when creating notes of that type.
Optional `config.default_tags` (YAML array) are merged with user-supplied tags
when the note is created. The `config` attribute is automatically removed from
the final note file.

Example template with config.path:

```yaml
--- 
id: "<%= id %>" 
type: journal
date: "<%= date %>" 
title: "<%= title %>" 
tags: <%= tags %> 
config: 
  path: "journal/<%= date %>.md" 
--- 
```

### Indexing

`ZettelHub` provides the capability for notes to be indexed into a Sqlite
database. The indexer extracts metadata contained in the YAML front matter of a
note, and inserts this into a Sqlite table along with a unique ID and the file
path, relative to the notebook directory for each note.

The indexer uses SQLite FTS5 (Full-Text Search) to enable fast full-text
searching across note titles, filenames, and body content. The FTS index is
automatically maintained through database triggers, ensuring search results stay
synchronized with note updates.

Search is **interactive by default** (fzf with preview). Use **`--list`**,
**`--table`**, or **`--json`** (or **`--format list|table|json`**) to print
results to stdout instead. Filter by type, tag, date, and path.

### Tag management

- **`zh tags`** – List all tags with note counts.
- **`zh tag add TAG NOTE_ID`** – Add a tag to a note (by id).
- **`zh tag remove TAG NOTE_ID`** – Remove a tag from a note.
- **`zh tag rename OLD_TAG NEW_TAG`** – Rename a tag across all notes.

Example: `zh tag add work abc12345` adds the tag "work" to the note with id
`abc12345`.

### Version control (Git integration)

`ZettelHub` includes built-in Git integration for tracking note history and
syncing with remote repositories.

**Core git commands:**

- **`zh git init`** – Initialize a git repository in your notebook. Creates
  `.gitignore` to exclude the `.zh/` directory.
- **`zh git init --remote URL`** – Initialize and set a remote repository URL.
- **`zh git status`** – Show notebook status with note titles alongside file
  paths.
- **`zh git commit -m "message"`** – Commit changes with a message.
- **`zh git commit --all`** – Stage and commit all changes (auto-generates
  message).
- **`zh git sync`** – Pull then push with the configured remote.
- **`zh git sync --push-only`** / **`--pull-only`** – One-way sync.

**History and restoration:**

- **`zh history NOTE_ID`** – View git history for a note. Interactive by default
  (fzf with preview); use `--list`, `--table`, or `--json` for output to stdout.
- **`zh diff NOTE_ID`** – Show uncommitted changes to a note.
- **`zh diff NOTE_ID --staged`** – Show staged changes.
- **`zh diff NOTE_ID COMMIT`** – Show changes at a specific commit.
- **`zh restore NOTE_ID COMMIT`** – Restore a note to a previous version.
- **`zh restore NOTE_ID COMMIT --preview`** – Preview what would change without
  restoring.

**Auto-commit (optional):**

Enable automatic commits after `add`, `tag`, and `import` operations:

```yaml 
git: 
  auto_commit: true 
  auto_push: false  # Enable to also push after each auto-commit 
  remote: origin 
  branch: main 
```

**Example workflow:**

```bash 
# Initialize git in your notebook 
zh git init --remote git@github.com:user/notes.git

# Create a note (auto-committed if auto_commit: true) 
zh add --title "Meeting Notes" --tags "work,project"

# View note history 
zh history abc12345

# Restore a previous version 
zh restore abc12345 a1b2c3d --preview  # Preview first 
zh restore abc12345 a1b2c3d            # Then restore

# Sync with remote 
zh git sync 
```

### Components

- **Main CLI tool:** `bin/zh` is a Bash script that routes to different command
  implementations.
- **Commands:**
  - all command implementations should be executable using `#!/usr/bin/env ruby`
    at the top of the file.
  - All command modules must implement command-specific `--help` (and `-h`) and
    the `--completion` option; see
    [AGENTS.md](AGENTS.md#help-system-requirements) and [Adding New
    Commands](AGENTS.md#adding-new-commands).
  - `lib/cmd/init.rb` (init), `lib/cmd/add.rb` (add), `lib/cmd/search.rb`
    (search), `lib/cmd/find.rb` (find), `lib/cmd/journal.rb` (today, yesterday,
    journal), `lib/cmd/reindex.rb` (reindex), `lib/cmd/tag.rb` (tag, tags).
- **Journal:** `zh today`, `zh yesterday`, and `zh journal <DATE>` open or
  create that day's journal entry (using the journal template) and open it in
  the editor. Config: `journal.path_pattern` (default `journal/{date}.md`),
  `tools.editor.journal.args` (default `{path}`).
- **Data Models:** 
  - `lib/models/note.rb` is the base note class definition for the default note.
    This class extends `document.rb` which is an abstract class. All other note
    types inherit from this base class.

## Documentation

For detailed information about the system architecture, design decisions, and
extension points, see:

- [ARCHITECTURE.md](ARCHITECTURE.md): Comprehensive architecture
  documentation including:
  - System overview and component architecture
  - Data flow diagrams
  - Configuration system
  - Extension points for adding new commands, document types, and templates
    (including adding command-specific configuration to
    [examples/config/config.yaml](examples/config/config.yaml) and
    [lib/config.rb](lib/config.rb))
  - Future architecture considerations

> [!NOTE]
> The majority of this documentation has been generated by a coding
> agent/assistant.

## Install and upgrade

Run `make install` to install the binary and symlink, and to install or update
global config and templates under `~/.config/ZettelHub/`.

- **First install**: Default config and bundled templates are written to
  `~/.config/zh/`.
- **Upgrade (existing config)**: The installer backs up your existing
  `config.yaml` and `templates/` to
  `~/.config/zh/backups/<YYYYMMDDHHMMSS>/`. It then merges the new
  defaults with your config (your values are kept) when the new version is not a
  breaking change (same or higher major version). When the bundled version has a
  **higher major** version than your config, the installer does **not**
  overwrite your config; it writes `config.yaml.new` (the new default) and
  `config.yaml.diff` (a unified diff) into the same backup directory so you can
  inspect and merge manually.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for the
full text.
