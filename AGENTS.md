# AGENTS.md

Quick reference for AI coding agents working in this repository.

## Build/Test Commands
- **All tests:** `make test` - Runs all Ruby unit tests and shell script tests
- **Single Ruby test:** `ruby -Ilib test/models/note_test.rb`
- **Single test file with test method:** `ruby -Ilib test/cmd/add_test.rb -n test_run_creates_note`
- **Shell tests:** `bats test/zk.bats`
- **Ruby lint:** `rubocop lib/`
- **Bash lint:** `shellcheck bin/zh`
- Use `Minitest` for Ruby unit tests,
- Use `bats` for shell script testing.

### Test Target Maintenance

The `make test` target automatically discovers and runs all test files matching the pattern `test/**/*_test.rb`. When adding new test files:

1. **Follow naming convention**: Test files must be named `*_test.rb` and placed in the `test/` directory (or subdirectories)
2. **Automatic discovery**: The Makefile uses a `for` loop to find all test files - no manual updates needed
3. **Test structure**: Tests should follow the existing pattern using Minitest
4. **Verification**: After adding tests, run `make test` to ensure they execute correctly

## Code Style Guidelines
- **Ruby:** CamelCase classes, snake_case methods/variables, `require_relative` for local files, `require` for external. Use `frozen_string_literal: true`
- **Bash:** POSIX compliant, use `#!/bin/bash` or `#!/usr/bin/env ruby` for Ruby scripts, double quotes for variables
- **Error handling:** `exit 1` for failures, `puts` for user messages
- **Imports:** Group requires at top, use relative paths for local modules
- **IO.popen:** Always pass the user's environment: use `IO.popen(ENV.to_h, cmd, mode)`. When adding custom env vars, use `ENV.to_h.merge(...)` so the user's environment is preserved.
- **Naming:** Descriptive names, consistent with existing codebase
- **Comments:** Document all Ruby code per [Ruby RDoc documentation](#ruby-rdoc-documentation); avoid inline comments for obvious code
- **Formatting:** Follow Rubocop standards, consistent indentation
- **Testing:** Use Minitest for Ruby unit tests, bats for shell script testing
- **Markdown Construction:** Always use CommonMarker library to construct markdown documents programmatically. Avoid creating markdown by concatenating strings. Parse content with CommonMarker to validate and format, then use CommonMarker's document objects and `to_commonmark` method for output.
- **Language:** Bash for cli commands and function wrappers, Ruby for library
  and implementation. Try to be POSIX compliant.
- **Code Style:** Use `Rubocop` for Ruby style and linting. Use `shellcheck` for
  bash linting.
- **External tools:** Use external tools such as `gum`, fzf`, `ripgrep`, `bat`
  for providing user interaction. Sqlite is used for database and indexing
    operations.

### Ruby RDoc documentation

All Ruby sources in `lib/` must follow the [Ruby RDoc](https://ruby.github.io/rdoc/) specification for in-code documentation.

- **Placement**: Put a comment block **immediately above** each class, module, method, and constant (no blank line between comment and definition).
- **Classes/Modules**: One-line summary required; optional second line for context.
- **Methods**: One sentence describing purpose; add params/return in prose when non-obvious (e.g. "Returns note_id or nil", "Raises ArgumentError if path is missing").
- **Constants**: One-line comment on same line or block above.
- **New code**: When adding new classes, modules, methods, or files, add the corresponding RDoc comment so the codebase stays compliant.

Formal `@param`/`@return` or `call-seq` are optional; simple prose above each definition is sufficient.

### Debugging output

**REQUIRED**: All modules and methods must provide debugging output so that behavior can be inspected when `ZH_DEBUG=1` is set.

- **Commands and services**: Include the `Debug` module (`require_relative '../debug'`, `include Debug`). Use `debug?` to guard debug-only logic and `debug_print(message)` to emit lines to stderr. Pass `debug: debug?` when calling Config or other code that accepts a debug option.
- **What to log**: For each significant step, decision, or outcome, emit a concise debug line (e.g. inputs, resolved paths, counts, errors). Examples: notebook path and file count at scan start; per-item progress where useful; summary counts and any orphan/removal info after a pass.
- **No new flags**: Debug is enabled only via the `ZH_DEBUG=1` environment variable; do not add a `--debug` CLI flag for this purpose.
- **New code**: When adding or changing modules or methods, add or extend `debug_print` calls so that the new paths and outcomes are visible under `ZH_DEBUG=1`.

## Project Overview
`ZettelHub` is a CLI tool for Zettelkasten note management using CommonMark Markdown with YAML front matter. Uses ERB templates, SQLite indexing. Journal commands: `zh today`, `zh yesterday`, `zh journal <DATE>` open or create that day's journal entry and open in the configured editor (config: `journal.path_pattern`, `tools.editor.journal`).

### Installer and config versioning

- **Ruby helpers**: All Ruby helpers and install-time logic live in `lib/` (e.g. `lib/install_config.rb`). Do not add install or config-merge logic under `scripts/`.
- **Breaking config changes**: Only **major** releases may introduce breaking config changes. When introducing a breaking config change: bump the project **major** version in `VERSION`, set `config_version` in `examples/config/config.yaml` to the new version string, and document the change in CHANGELOG. The installer will then write `config.yaml.new` and `config.yaml.diff` to `~/.config/ZettelHub/backups/<datestamp>/` instead of overwriting the user's config, so users can inspect and merge manually.

## Template Quoting Requirements

**CRITICAL**: When creating or modifying ERB templates (`.erb` files in `lib/templates/` or user template directories), you MUST follow YAML quoting rules to prevent parsing errors.

### Required Quoting Rules

1. **String values MUST be quoted** if they may contain special YAML characters (`:`, `#`, `[`, `]`, `&`, `*`, `!`, `|`, `>`, `'`, `"`, `%`, `@`, `` ` ``):
   ```yaml
   title: "<%= title %>"      # ✓ Correct: quoted
   date: "<%= date %>"         # ✓ Correct: quoted
   aliases: "<%= aliases %>"   # ✓ Correct: quoted
   id: "<%= id %>"             # ✓ Correct: quoted
   ```

2. **The `config.path` field MUST always be quoted** since it may contain special characters from interpolated variables:
   ```yaml
   config:
       path: "<%= id %>-<%= title %>.md"  # ✓ Correct: quoted
       path: <%= id %>-<%= title %>.md     # ✗ WRONG: unquoted (will fail with special chars)
   ```

   **Default tags:** Templates can define `config.default_tags` (YAML array) in the front matter. When a note is created, these are merged with user-supplied tags (defaults first, then supplied tags, then `uniq`). The entire `config` block (including `path` and `default_tags`) is removed from the written file. Default tags are taken only from the template content; they are not configured in config.yaml or config.rb.

3. **The `tags` field MUST NOT be quoted** since it's rendered as an inline YAML array by the `add` command:
   ```yaml
   tags: <%= tags %>           # ✓ Correct: unquoted (renders as ["tag1", "tag2"])
   tags: "<%= tags %>"         # ✗ WRONG: quoted (would render as string, not array)
   ```

### Why This Matters

- **Unquoted values with special characters** (especially `:` in titles) cause YAML parsing errors: `"did not find expected key while parsing a block mapping"`
- **Quoted `tags`** prevents proper array parsing, storing tags as strings instead of arrays
- **Unquoted `config.path`** breaks when titles contain `:`, `#`, or other special characters

### Template Examples

**Correct template structure:**
```yaml
---
id: "<%= id %>"
type: note
date: "<%= date %>"
title: "<%= title %>"
aliases: "<%= aliases %>"
tags: <%= tags %>
description: "<%= description %>"
config:
    path: "<%= id %>-<%= title %>.md"
---

# <%= title %>

<%= content %>
```

**Template variables:** In addition to `id`, `type`, `date`, `title`, `aliases`, `tags`, `content`, templates have: `description` (optional short overview); and time variables: `year`, `month`, `day`, `week`, `week_year`, `month_name`, `month_name_short`, `day_name`, `day_name_short`, `time`, `time_iso`, `hour`, `minute`, `second`, `timestamp`. Use these in `config.path` in the template front matter (e.g. `journal/<%= year %>/w<%= week %>.md`).

**When modifying templates:**
- Always quote string fields that use ERB interpolation: `"<%= variable %>"`
- Always quote `config.path` values: `path: "<%= pattern %>"`
- Optional: add `config.default_tags` (YAML array) to merge with user-supplied tags; the `config` block is removed from output.
- Never quote the `tags` field: `tags: <%= tags %>`
- Test templates with special characters in titles (e.g., `"Test: Note #1"`) to verify YAML parsing

### Template discovery

Templates are **discovered** by enumerating `.erb` files; they are not listed in config. Search order (later overrides earlier): bundled (`lib/templates/`), global (`~/.config/ZettelHub/templates/`), local (`.zh/templates/` within the notebook). The template **type** (e.g. `note`, `journal`, `meeting`) is inferred from the `type` key in each template's YAML front matter. The output path is taken only from the template's **`config.path`** in front matter (variable interpolation is applied). There is no `templates` key in config and no `filename_pattern` or `subdirectory` in config.

See [README.md](README.md#template-files) and [ARCHITECTURE.md](ARCHITECTURE.md) for more details on template structure and requirements.

## Known Bug Patterns to Avoid

### ERB Variable Shadowing in Template Rendering

**CRITICAL**: When rendering ERB templates with `context.instance_eval { binding }`, method parameters in the enclosing scope will shadow context methods of the same name.

**Problem**: If a method has parameters like `title: nil, tags: nil`, and you render ERB with:
```ruby
def render_template(..., title: nil, tags: nil, ...)
  context = OpenStruct.new(vars)  # vars['title'] = "My Title"
  template.result(context.instance_eval { binding })  # ERB sees title = nil!
end
```
The `title` parameter (which is `nil` when not provided via CLI) shadows `context.title` in the ERB binding. ERB evaluates `<%= title %>` as the local variable `nil` instead of calling `context.title`.

**Solution**: Extract ERB rendering to a separate helper method that has no local variables matching template variable names:
```ruby
def render_template(..., title: nil, ...)
  # ... build vars ...
  render_erb_with_context(template_file, vars, config)  # Separate method!
end

def render_erb_with_context(template_file, vars, config)
  template = ERB.new(File.read(template_file))
  context = OpenStruct.new(vars)
  # No 'title', 'tags', etc. local variables here!
  template.result(context.instance_eval { binding })
end
```

### Wikilink Resolution with Display Text

**Problem**: Wikilinks like `[[9fb61e1a|Clientele Ltd]]` contain both an ID and display text separated by `|`. When resolving wikilinks, the full inner content must be parsed to extract just the target (ID/title) portion.

**Wrong**:
```ruby
def resolve_wikilink_to_id(link_text, db)
  inner = link_text.strip  # "9fb61e1a|Clientele Ltd"
  if inner =~ /\A[a-f0-9]{8}\z/i  # Never matches!
    # ...
  end
end
```

**Correct**:
```ruby
def resolve_wikilink_to_id(link_text, db)
  inner = link_text.strip
  # Parse out the target before the | delimiter
  target = inner.include?('|') ? inner.split('|', 2).first.strip : inner
  if target =~ /\A[a-f0-9]{8}\z/i  # Now matches "9fb61e1a"
    # ...
  end
end
```

### Gum Prompt Visibility

**Problem**: Using only `--placeholder` for `gum input` shows greyed-out text inside the input field, which users may not notice.

**Better**: Use `--header` to show the prompt label above the input field:
```ruby
# Instead of:
cmd = ['gum', 'input', '--placeholder', 'Meeting title']

# Use:
cmd = ['gum', 'input', '--header', 'Meeting title', '--placeholder', 'Type here...']
```

## Architecture Documentation

- **Main documentation**: [ARCHITECTURE.md](ARCHITECTURE.md) - Comprehensive architecture guide

### Architecture Documentation Maintenance

When making architectural changes, update ARCHITECTURE.md when:
- Adding new components (commands, models, services)
- Changing component behavior significantly
- Introducing new patterns
- Changing dependencies or file structure

See [ARCHITECTURE.md](ARCHITECTURE.md#architecture-documentation-maintenance) for detailed maintenance guidelines.

## Directives
- Follow established patterns and architecture
- Ensure test coverage for new features
- Keep changes focused and modular
- Use external tools: gum, fzf, ripgrep, bat, sqlite
- External tools that support a version flag can be checked with `--version` (e.g. `bat --version`, `fzf --version`, `rg --version`, `glow --version`, `bats --version`, `shellcheck --version`). Minimum versions are not specified; use recent stable releases.
- Update architecture documentation when making architectural changes
- **CRITICAL**: When creating or modifying ERB templates, follow [Template Quoting Requirements](#template-quoting-requirements) to prevent YAML parsing errors
- **MANDATORY**: After adding new features or making changes, **always run `make test`** to validate all unit tests pass. Never commit changes without verifying tests pass. If tests fail, fix the issues before proceeding.
- **REQUIRED**: When adding new features, updating existing functionality, or adding to the model layer, **evaluate test coverage** and create new tests as needed. Review existing tests to identify gaps, add tests for new code paths, edge cases, and error conditions. Ensure all new functionality has corresponding test coverage before completing the work.
- **REQUIRED**: All modules and methods must provide debugging output when `ZH_DEBUG=1` is set; see [Debugging output](#debugging-output).
- **REQUIRED**: Document all new Ruby classes, modules, methods, and constants per the Ruby RDoc specification; see [Ruby RDoc documentation](#ruby-rdoc-documentation).
- **REQUIRED**: When adding a new **external tool** (new `tools.<name>.command` or dependency on a binary), update [README.md](README.md#requirements) with the tool name and whether it is required or optional; when adding a new **Ruby gem**, add it to the Gemfile and list it under README → Requirements (runtime vs development).
- **Follow coding standards:** Adhere to all guidelines outlined in the `Code
  Style` section.
- **Explain reasoning:** Briefly explain your thought process or plan before
  suggesting or making a code change.
- **Use existing patterns:** Prioritize using existing architecture, design
  patterns, and utility functions.
- **Ensure test coverage:** When adding new features, include new or updated
  unit tests to ensure adequate coverage.
- **Keep changes focused:** Aim for small, modular, and logical code changes.

## Help System Requirements

The CLI provides a comprehensive help system via the `--help` or `-h` flags. **Every command MUST implement command-specific help.** The router passes `--help`/`-h` through to the module; the module must handle them and print help (do not intercept in the router).

### Help Implementation

- **Top-level help**: `zh --help` or `zh -h` displays general usage and all available commands (from `show_help()` in `bin/zh`)
- **Command-specific help**: `zh <command> --help` or `zh <command> -h` displays that command's help. The router passes these flags to the Ruby module; the module must handle them and print its own help.
- **Help function**: The `show_help()` function in `bin/zh` contains the general help text and should be updated when adding new commands so top-level `zh --help` stays complete.

### Help Requirements for New Commands

When adding a new command:

1. **Update `show_help()` function** in `bin/zh`:
   - Add the new command to the COMMANDS section with description
   - Add usage examples if appropriate
   - Ensure the command is listed in the correct order

2. **Do NOT add `--help` interception in the router**: The command route in `bin/zh` must pass all arguments (including `--help`/`-h`) to the Ruby module. Example: `ruby "$DIR/../lib/cmd/commandname.rb" "$@"`. Do not check for `--help` in the shell and call `show_help`; let the module handle it.

3. **Implement command-specific help (REQUIRED)** in the module: At the start of `run(*args)`, add `return output_help if args.first == '--help' || args.first == '-h'`. Implement a private `output_help` method with USAGE, DESCRIPTION, OPTIONS (at least `--help`, `-h`, `--completion`), and EXAMPLES, following the format of existing commands (e.g. [lib/cmd/links.rb](lib/cmd/links.rb)).

### Help Content Guidelines

- Help text should be clear and concise
- Help format must be consistent: USAGE, DESCRIPTION, OPTIONS, EXAMPLES
- Include usage syntax for each command
- Provide examples for common use cases
- Use heredoc (`cat << 'EOF'`) for multi-line help text in shell functions; in Ruby use `puts <<~HELP` ... `HELP` for command-specific help

## Adding New Commands

When adding a new command to `lib/cmd/`, follow this checklist:

1. **Create command file**: `lib/cmd/{command_name}.rb`
   - Use executable Ruby script pattern (`#!/usr/bin/env ruby`)
   - Include `frozen_string_literal: true`
   - Implement command class with `run` method

2. **Add route in `bin/zh`** (pass all args to the module; do not intercept `--help`):
   ```bash
   commandname)
     [ "$DEBUG_MODE" -eq 1 ] && export ZH_DEBUG=1
     ruby "$DIR/../lib/cmd/commandname.rb" "$@"
     ;;
   ```

3. **Implement command-specific help** (REQUIRED): Handle `--help`/`-h` in `run` and implement `output_help` with USAGE, DESCRIPTION, OPTIONS, EXAMPLES. See [Help System Requirements](#help-system-requirements).

4. **Update help function** (REQUIRED):
   - Add the new command to the `show_help()` function in `bin/zh`
   - Include command description and usage examples
   - See [Help System Requirements](#help-system-requirements) for details

5. **Implement completion** (REQUIRED):
   - Add `--completion` option handling in `run` method:
     ```ruby
     def run(*args)
       return output_completion if args.first == '--completion'
       # Normal command logic
     end
     ```
   - Implement `output_completion` private method:
     ```ruby
     private
     
     def output_completion
       # Return space-separated completion candidates
       # Example: puts 'arg1 arg2 arg3'
       # Or empty if no arguments: puts ''
       puts ''
     end
     ```
   - Commands automatically appear in shell completion
   - No bash script changes needed - completion is dynamically discovered

6. **Add command configuration and external tools** (if the command needs it):
   - **External tools**: If the command invokes external tools (editor, preview, filter, matcher, etc.), follow the [External tools in command modules](#external-tools-in-command-modules) pattern. The command module **MUST** define a **`REQUIRED_TOOLS`** constant (array of config keys, e.g. `%w[matcher filter]`) and validate each tool's executable before running. Do not add new full-command getters; use `Config.get_tool_command`, `Config.get_tool_module_args`, and `Config.get_tool_module_opts` and build the invocation in the command module.
   - **Other options**: For non-tool options (e.g. limits, globs), add a top-level section (e.g. `mycommand:` like `search:` / `find:`) in [examples/config/config.yaml](examples/config/config.yaml) and getters in [lib/config.rb](lib/config.rb) using `dig_config` with the appropriate path.
   - Add or extend tests in `test/config_test.rb` for any new config getters. For tool defaults, the existing `get_tool_command` / `get_tool_module_args` / `get_tool_module_opts` tests cover the pattern; add tests only if you introduce new default behavior.
   - See [ARCHITECTURE.md](ARCHITECTURE.md#hierarchical-config-layout) and [examples/config/config.yaml](examples/config/config.yaml) for the full layout.

7. **Evaluate test coverage and add tests**: `test/cmd/{command_name}_test.rb`
   - **Evaluate existing test coverage**: Review related test files to identify gaps
   - **Create comprehensive tests** for:
     - All code paths and branches
     - Edge cases and error conditions
     - Input validation and argument parsing
     - Integration with other components
   - Test files are automatically discovered by `make test` (no Makefile update needed)
   - Follow naming convention: `*_test.rb`
   - Use Minitest framework
   - **Run `make test` to verify all tests pass before committing**

8. **Update documentation**: See [ARCHITECTURE.md](ARCHITECTURE.md#adding-new-commands) for details. Add RDoc comments above the command class and above each method (run, output_help, output_completion, and any other public or private method); see [Ruby RDoc documentation](#ruby-rdoc-documentation).

9. **Validate tests** (REQUIRED):
   - Run `make test` to ensure all tests pass
   - Fix any test failures before proceeding
   - Verify new tests execute correctly
   - Ensure no tests trigger interactive prompts (all inputs must be provided via command-line arguments)
   - **Evaluate test coverage**: Ensure new functionality is adequately tested

**Completion Requirements**:
- All commands MUST implement `--completion` option
- All commands MUST also implement command-specific `--help`/`-h` as described in [Help System Requirements](#help-system-requirements)
- Commands with no arguments should return empty string (`puts ''`)
- Commands with arguments should return space-separated candidates
- Completion is automatically integrated - no manual bash script updates needed

### External tools in command modules

When a command module uses external tools (e.g. editor, preview, filter, matcher), it MUST follow this pattern so configuration stays consistent and only the executable is validated for availability.

- **Config shape**: In `tools`, each tool has:
  - **`tools.<tool>.command`**: The **executable only** (e.g. `vim`, `fzf`, `rg`). This is what is checked for availability (e.g. `Utils.require_command!` or `Utils.command_available?`).
  - **`tools.<tool>.<module>.args`**: Placeholder string for this command module (e.g. for `find`: `{1} +{2}` for editor; find uses `{1}` = path, `{2}` = line).
  - **`tools.<tool>.<module>.opts`**: Array of static CLI options (e.g. `['--ansi', '--disabled']` for filter in find).

- **Config API** (use these only; do not add new full-command getters):
  - **`Config.get_tool_command(config, tool_key)`** → executable string (with defaults when missing).
  - **`Config.get_tool_module_args(config, tool_key, module_name)`** → args string for that tool and module (e.g. `module_name` = `'find'`, `'search'`, `'add'`).
  - **`Config.get_tool_module_opts(config, tool_key, module_name)`** → array of option strings.

- **In the command module**:
  1. **`REQUIRED_TOOLS` (REQUIRED)**: Every command module that uses external tools MUST define a constant listing the config keys of tools it requires (e.g. `REQUIRED_TOOLS = %w[matcher filter].freeze`). Before running, loop over `REQUIRED_TOOLS` and for each key call `Utils.require_command!(Config.get_tool_command(config, key), message)` so the command exits with a clear error if the executable is missing. Example:
     ```ruby
     REQUIRED_TOOLS = %w[matcher filter].freeze

     # In run, after loading config:
     REQUIRED_TOOLS.each do |tool_key|
       executable = Config.get_tool_command(config, tool_key)
       next if executable.to_s.strip.empty?
       msg = "Error: tool '#{tool_key}' (#{executable}) is required for zh find. Install #{executable} and try again."
       Utils.require_command!(executable, msg)
     end
     ```
     If the command uses no external tools, omit `REQUIRED_TOOLS` and this validation.
  2. **Building the invocation**: Get executable, opts, and args from Config, then build the final command string or array:
     - **String** (e.g. for fzf `execute()`): `[executable, *opts, args].reject(&:empty?).join(' ')`. The `args` string may contain placeholders (e.g. `{1}`, `{2}`) that fzf or the caller substitutes later; do not substitute in the command module unless you are invoking the command yourself.
     - **Array** (e.g. for `IO.popen`): `[executable, *opts, ...module-specific args]`.
  3. **Fallbacks**: If a tool is optional (e.g. preview: bat vs cat), check availability with `Utils.command_available?(Config.get_tool_command(config, 'preview'))` and choose executable/args/opts accordingly; still use `get_tool_module_args` / `get_tool_module_opts` for the chosen tool or a simple default (e.g. `cat` with args `'{1}'`).

- **Adding a new command module that uses tools**: In [examples/config/config.yaml](examples/config/config.yaml), add a `<module>` key under each tool that the command uses (e.g. `tools.editor.mycommand.args`, `tools.editor.mycommand.opts`). In [lib/config.rb](lib/config.rb), add defaults for that module in `default_tool_module_args` and `default_tool_module_opts` (the `case [tool_key, module_name]` in those methods). Do not add new getters that return a full command string.

- **Filter keybindings**: Keybindings follow the uniform convention in config (`tools.filter.keybindings`). Each module MUST build its own `editor_command`, `reader_command`, and `open_command` and pass them to `Config.substitute_filter_keybinding_placeholders`. Do not add enter/ctrl-r/ctrl-o (or other default keys) in code. Modules may add one or more module-specific keybindings provided they do not conflict with the default keys defined in config / `default_tools_filter_keybindings`.

- **Examples**: See `lib/cmd/find.rb` (REQUIRED_TOOLS, `build_tool_invocation`, use of get_tool_command / get_tool_module_args / get_tool_module_opts) and `lib/cmd/search.rb` (same pattern for interactive search).

## Test Coverage Requirements

When adding new features, updating existing functionality, or adding to the model layer, you MUST evaluate and ensure adequate test coverage:

### Test Coverage Evaluation Process

1. **Review existing tests**:
   - Check related test files in `test/` directory
   - Identify what's already covered
   - Find gaps in coverage for new/changed functionality

2. **Create comprehensive tests** for:
   - **New features**: All code paths, branches, and public methods
   - **Model additions**: Initialization, attribute access, inheritance, edge cases
   - **Command updates**: Argument parsing, error handling, integration points
   - **Edge cases**: Invalid inputs, boundary conditions, error scenarios
   - **Integration**: Interactions between components

3. **Test file locations**:
   - Commands: `test/cmd/{command_name}_test.rb`
   - Models: `test/models/{model_name}_test.rb`
   - Utilities: `test/utils_test.rb`
   - Configuration: `test/config_test.rb`
   - Integration: `test/zk.bats` (shell script tests)

4. **Test requirements**:
   - All tests must pass (`make test`)
   - No tests should trigger interactive prompts (provide all inputs via arguments)
   - Tests should be isolated and not depend on external state
   - Follow existing test patterns and naming conventions

5. **Coverage checklist**:
   - [ ] New code paths are tested
   - [ ] Error conditions are tested
   - [ ] Edge cases are covered
   - [ ] Integration with other components is tested
   - [ ] All tests pass before committing

### Model-Specific Test Coverage

When adding or updating models (`lib/models/`):
- Test initialization with various input formats (symbol keys, string keys)
- Test attribute access and assignment
- Test inheritance relationships (if extending Document or Note)
- Test file parsing and front matter extraction
- Test error handling (missing files, invalid data)
- Test metadata handling and special characters
- Review existing model tests (`test/models/*_test.rb`) for patterns

## Commit Types
- `feat`: New features/API changes
- `fix`: Bug fixes
- `refactor`: Code restructuring
- `test`: Test additions/corrections
- `docs`: Documentation only
- `style`: Code style/formatting
- `build/ops/chore`: Build/operational/misc changes

## Versioning

The project uses **semantic versioning** `x.y.z` (see the `VERSION` file):

- **x (major)**: Major changes; **only major releases may introduce breaking
  changes** (e.g. removed or renamed config keys, changed value types).
- **y (minor)**: New features; may add new config keys but **must not change the
  types of existing keys**.
- **z (patch)**: Bug fixes; no config schema impact.

The example config includes an optional top-level `config_version` key aligned
with the project version (e.g. `config_version: "0.2.13"`). The installer uses
the **major** version to decide whether to merge your config with the new
defaults or to write a diff for manual merge when a breaking change is
introduced.
