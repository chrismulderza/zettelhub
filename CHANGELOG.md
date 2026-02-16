# Changelog

## 0.1.1

### New Features

- **Contact Management**: Added Person, Organization, and Account models with dedicated commands (`zh person`, `zh org`) for contact and organization management
- **Dynamic Template Prompts**: Templates can define interactive prompts with `optional` and `multi` flags for conditional and multi-select input
- **Unified Theme System**: Added `zh theme` command with bundled themes (Nord, Dracula, Tokyo-Night, Gruvbox, Catppuccin) for consistent styling across gum, fzf, bat, and glow
- **VCF Interoperability**: Import/export contacts in vCard format via `zh person import/export`
- **Neovim Integration**: Added Lua plugin with nvim-cmp completion for wikilinks/tags/mentions, Telescope pickers, and wikilink navigation
- **Note Display**: Added `zh show` command for formatted note output with template support
- **Wikilink Resolution**: Added `zh resolve` command for resolving wikilinks to note paths
- **Organization Hierarchy**: Added tree, ancestors, and descendants traversal for organization parent/subsidiary relationships

### Bug Fixes

- Fixed ERB variable shadowing in template rendering that caused variables like `title` to render empty when method parameters shadowed OpenStruct context
- Fixed wikilink resolution for links with display text (`[[id|Title]]`) by parsing out target ID before the `|` delimiter
- Improved gum prompt visibility by using `--header` flag for prompt labels

### Documentation

- Added "Known Bug Patterns to Avoid" section to AGENTS.md documenting ERB shadowing, wikilink parsing, and gum prompt patterns
- Updated ARCHITECTURE.md with ERB rendering isolation, dynamic prompt flags, and wikilink resolution details

## 0.1.0

- Initial release of ZettelHub.
