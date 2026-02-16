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
- A person (contact) type
- An organization type
- A bookmark type

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
  - **Person**: Contact/people management (extends Document)
  - **Organization**: Companies, institutions, groups (extends Document)
    - Account : Customer accounts (extends Organization)

### Template files

Template files are developed using Embedded Ruby (ERB), allowing for
placeholders to be replaced in the YAML front matter, and the body of the note.

Templates support **dynamic prompts** that collect user input interactively:
- Multiple prompt types: `input`, `write`, `choose`, `filter`, `confirm`
- **Multi-select**: Use `multi: true` for selecting multiple items (e.g., meeting attendees)
- **Optional fields**: Use `optional: true` to prompt for confirmation before collecting
- **Dynamic sources**: Populate options from tags, notes, files, or external commands
- **Validation**: Built-in validators for URLs, emails, dates, and custom patterns
- **Transformations**: Transform input with `split`, `slugify`, `trim`, etc.

See [docs/TEMPLATES.md](docs/TEMPLATES.md) for detailed documentation on the
template system with examples.

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
- **`zh tags --source frontmatter`** – List only front matter tags.
- **`zh tags --source body`** – List only body hashtags.
- **`zh tag add TAG NOTE_ID`** – Add a tag to a note (by id).
- **`zh tag remove TAG NOTE_ID`** – Remove a tag from a note.
- **`zh tag rename OLD_TAG NEW_TAG`** – Rename a tag across all notes.

Tags are stored in a unified index from two sources: front matter (`tags: [...]`)
and body hashtags (`#tagname`). The `zh tags` command shows tag counts with their
source(s).

Example: `zh tag add work abc12345` adds the tag "work" to the note with id
`abc12345`.

### Contact Management (Person)

- **`zh person`** – Interactive contact browser (fzf).
- **`zh person add`** – Create a new contact (prompts for details).
- **`zh person list`** – List all contacts in table format.
- **`zh person list --json`** – Output contacts as JSON.
- **`zh person import FILE`** – Import contacts from vCard (.vcf) file.
- **`zh person export`** – Export contacts to vCard format.
- **`zh person birthdays`** – Show upcoming birthdays.
- **`zh person stale`** – Show contacts not recently contacted.
- **`zh person merge ID1 ID2`** – Merge duplicate contacts.

Contacts support `@Name` aliases for concise wikilink references: `[[@John Doe]]`.

### Organization Management

- **`zh org`** – Interactive organization browser.
- **`zh org add`** – Create new organization.
- **`zh org add --type account`** – Create new customer account.
- **`zh org list`** – List all organizations/accounts.
- **`zh org tree NOTE_ID`** – Display organization hierarchy tree.
- **`zh org parent NOTE_ID`** – Show parent organization.
- **`zh org subs NOTE_ID`** – List direct subsidiaries.
- **`zh org ancestors NOTE_ID`** – List all ancestor organizations.
- **`zh org descendants NOTE_ID`** – List all descendants.

Organizations support parent/subsidiary relationships via wikilinks in metadata.

### Theming

ZettelHub provides a unified theming system that applies consistent colors across
all CLI tools (gum, fzf, bat, glow, ripgrep).

**Built-in themes:**
- `nord` - Arctic, north-bluish palette (default)
- `dracula` - Dark theme with vibrant colors
- `tokyo-night` - Clean dark theme, Tokyo lights
- `gruvbox` - Retro groove, warm tones
- `catppuccin` - Soothing pastel (Mocha variant)

**Theme commands:**
- **`zh theme list`** - List available themes
- **`zh theme preview NAME`** - Preview theme colors in terminal
- **`zh theme export NAME`** - Output shell environment variables
- **`zh theme apply NAME`** - Write config files (glow style, etc.)

**Configuration:**

Set theme in `config.yaml`:
```yaml
theme: nord
```

Or customize with a full palette:
```yaml
theme:
  name: custom
  palette:
    accent: "#88C0D0"
    accent_secondary: "#81A1C1"
    # ... see examples/config/config.yaml for all keys
```

**Shell integration:**

Add to `~/.bashrc` or `~/.zshrc`:
```bash
eval "$(zh theme export)"
```

For fish shell, add to `~/.config/fish/config.fish`:
```fish
zh theme export --fish | source
```

### Neovim Integration

ZettelHub provides seamless Neovim integration with completion, navigation, and
automatic indexing.

**Features:**
- **Inline completion**: Type `[[` for wikilinks, `[[@` for @person mentions, `#` for tags
- **Telescope pickers**: Browse notes, insert links, select people/organizations
- **Link navigation**: `gf` follows wikilinks and markdown links under cursor
- **Create on missing**: `gF` offers to create notes for unresolved links
- **Hover preview**: `K` shows note preview in floating window
- **Backlinks/Forward links**: Telescope pickers for link exploration
- **Auto-indexing**: Notes are automatically reindexed when saved

**Quick setup** (after `make install`):

```lua
vim.opt.runtimepath:append(vim.fn.expand('~/.config/zh/nvim'))
require('zettelhub').setup()
```

See [docs/NEOVIM_INTEGRATION.md](docs/NEOVIM_INTEGRATION.md) for complete setup
instructions, keymaps, and configuration options.

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
  - `lib/models/person.rb` – Contact/people management model.
  - `lib/models/organization.rb` – Organization model with hierarchy support.
  - `lib/models/account.rb` – Customer accounts (extends Organization).

## Documentation

### User Documentation

- [docs/TEMPLATES.md](docs/TEMPLATES.md): Complete guide to the template system
  including dynamic prompts, variables, validation, and examples.
- [docs/NEOVIM_INTEGRATION.md](docs/NEOVIM_INTEGRATION.md): Neovim setup guide
  with completion, navigation, keymaps, and Telescope pickers.

### Developer Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md): System architecture, component design,
  data flow, configuration system, and extension points.
- [AGENTS.md](AGENTS.md): Guidelines for AI coding agents including code style,
  testing, and common patterns.
- [TODO.md](TODO.md): Feature roadmap and implementation status.

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
