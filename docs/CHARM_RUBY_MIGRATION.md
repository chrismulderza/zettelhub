# Charm Ruby Migration Plan

This document outlines a plan to replace ZettelHub's external CLI tool dependencies (gum, fzf, glow, bat) with native Ruby libraries from the [Charm Ruby](https://charm-ruby.dev/) ecosystem.

## Overview

The Charm Ruby ecosystem provides Ruby ports of Charm's Go libraries, enabling glamorous terminal UIs without external tool dependencies.

## Current Dependencies vs Charm Ruby Replacements

| Current Tool | Purpose | Charm Ruby Replacement | Status |
|--------------|---------|----------------------|--------|
| `gum` | Interactive prompts | **`huh`** gem | ✅ Available |
| `fzf` | Fuzzy filtering | **`bubbles`** List | ✅ Available |
| `glow` | Markdown rendering | **`glamour`** gem | ✅ Available |
| `bat` | Syntax highlighting | **`lipgloss`** | ✅ Available |
| `ripgrep` | Fast search | No replacement | Keep external |

## Gemfile Additions

```ruby
# Charm Ruby UI libraries
gem "huh", github: "marcoroth/huh-ruby"  # Forms/prompts (replaces gum)
gem "bubbletea"                           # TUI framework
gem "bubbles"                             # TUI components (list, spinner, etc.)
gem "lipgloss"                            # Styling and tables
gem "glamour"                             # Markdown rendering (replaces glow)
```

## Charm Ruby Libraries

### huh - Forms and Prompts

Repository: https://github.com/marcoroth/huh-ruby

Replaces `gum` for interactive prompts. Provides:
- `Huh.input` - Single-line text input
- `Huh.text` - Multi-line text input
- `Huh.select` - Single selection from options
- `Huh.multi_select` - Multiple selection from options
- `Huh.confirm` - Yes/No confirmation
- Built-in validation and theming

```ruby
require "huh"

form = Huh.form(
  Huh.group(
    Huh.input
      .key("title")
      .title("Note title")
      .placeholder("Enter title..."),
    Huh.select
      .key("type")
      .title("Note type")
      .options(*Huh.options("note", "meeting", "journal")),
    Huh.confirm
      .key("open")
      .title("Open in editor?")
  )
).with_theme(Huh::Themes.charm)

form.run
puts "Title: #{form["title"]}"
puts "Type: #{form["type"]}"
```

### glamour - Markdown Rendering

Repository: https://github.com/marcoroth/glamour-ruby

Replaces `glow` for markdown preview. Provides:
- Multiple themes (dark, light, dracula)
- Custom styles via DSL
- Emoji support
- Configurable width

```ruby
require "glamour"

content = File.read("note.md")
puts Glamour.render(content,
  style: "dark",
  width: 80,
  emoji: true
)
```

### lipgloss - Styling and Layout

Repository: https://github.com/marcoroth/lipgloss-ruby

Provides terminal styling:
- Colors (hex, ANSI, adaptive)
- Borders, padding, margins
- Tables and lists
- Layout utilities

```ruby
require "lipgloss"

style = Lipgloss::Style.new
  .border(:rounded)
  .border_foreground("#88C0D0")
  .padding(1, 2)
  .bold(true)

puts style.render("Styled content")

# Tables
table = Lipgloss::Table.new
  .headers(["ID", "Title", "Type"])
  .rows([
    ["abc123", "Meeting Notes", "meeting"],
    ["def456", "Project Plan", "note"]
  ])
  .border(:rounded)

puts table.render
```

### bubbletea + bubbles - Interactive TUI

Repositories:
- https://github.com/marcoroth/bubbletea-ruby
- https://github.com/marcoroth/bubbles-ruby

TUI framework using Elm Architecture. Bubbles provides pre-built components:
- List (with filtering)
- Spinner
- Progress bar
- Text input
- Viewport

```ruby
require "bubbletea"
require "bubbles"

class NotePicker
  include Bubbletea::Model

  def initialize(notes)
    @list = Bubbles::List.new(notes)
  end

  def init
    [self, nil]
  end

  def update(message)
    case message
    when Bubbletea::KeyMessage
      return [self, Bubbletea.quit] if message.to_s == "q"
    end
    @list, cmd = @list.update(message)
    [self, cmd]
  end

  def view
    @list.view
  end
end

Bubbletea.run(NotePicker.new(notes))
```

## Proposed Architecture

```
lib/
├── ui/
│   ├── prompt.rb      # Wraps huh gem (input, select, confirm, etc.)
│   ├── picker.rb      # Wraps bubbletea+bubbles (fuzzy list selection)
│   ├── preview.rb     # Wraps glamour (markdown preview)
│   ├── table.rb       # Wraps lipgloss tables
│   └── theme.rb       # Theme integration with ZettelHub themes
```

## Migration Phases

### Phase 1: Markdown Preview (Low Risk)

**Goal**: Replace `glow` with `glamour`

1. Add `glamour` gem to Gemfile
2. Create `lib/ui/preview.rb`:

```ruby
# lib/ui/preview.rb
module UI
  class Preview
    def self.markdown(content, width: 80)
      require "glamour"
      Glamour.render(content, style: current_style, width: width, emoji: true)
    rescue LoadError
      # Fallback to glow or cat
      fallback_preview(content)
    end

    def self.current_style
      # Map ZettelHub theme to glamour style
      "dark"
    end
  end
end
```

3. Update preview commands to use `UI::Preview.markdown`
4. Keep `glow` as fallback

### Phase 2: Styled Output (Low Risk)

**Goal**: Replace `bat` for simple styled output with `lipgloss`

1. Add `lipgloss` gem to Gemfile
2. Create `lib/ui/style.rb`:

```ruby
# lib/ui/style.rb
require "lipgloss"

module UI
  class Style
    def self.box(content, title: nil)
      style = Lipgloss::Style.new
        .border(:rounded)
        .border_foreground(theme_accent)
        .padding(1, 2)

      style.render(content)
    end

    def self.table(headers, rows)
      Lipgloss::Table.new
        .headers(headers)
        .rows(rows)
        .border(:rounded)
        .render
    end

    def self.theme_accent
      # Get from ZettelHub theme
      "#88C0D0"
    end
  end
end
```

3. Keep `bat` for syntax highlighting (no good Ruby replacement)

### Phase 3: Prompts (Medium Risk) - **Biggest Win**

**Goal**: Replace `gum` prompts with `huh`

1. Add `huh` gem to Gemfile: `gem "huh", github: "marcoroth/huh-ruby"`
2. Create `lib/ui/prompt.rb`:

```ruby
# lib/ui/prompt.rb
require "huh"

module UI
  class Prompt
    class << self
      def input(label, default: nil, placeholder: nil, required: false)
        field = Huh.input
          .key("value")
          .title(label)
          .placeholder(placeholder || "Type here...")

        field = field.value(default) if default
        field = field.validate("Required") { |v| !v.to_s.strip.empty? } if required

        run_form(field)
      end

      def write(label, default: nil, placeholder: nil)
        field = Huh.text
          .key("value")
          .title(label)
          .placeholder(placeholder || "Type here...")

        field = field.value(default) if default
        run_form(field)
      end

      def select(label, options, default: nil)
        field = Huh.select
          .key("value")
          .title(label)
          .options(*Huh.options(*options))

        run_form(field)
      end

      def multi_select(label, options)
        field = Huh.multi_select
          .key("value")
          .title(label)
          .options(*Huh.options(*options))

        result = run_form(field)
        result.is_a?(Array) ? result : [result].compact
      end

      def confirm(label, default: false)
        field = Huh.confirm
          .key("value")
          .title(label)
          .affirmative("Yes")
          .negative("No")

        run_form(field) == true
      end

      def filter(label, options, default: nil, allow_new: false)
        # huh doesn't have built-in filter, use select
        # Could implement custom filtering with bubbletea
        select(label, options, default: default)
      end

      private

      def run_form(field)
        form = Huh.form(Huh.group(field)).with_theme(current_theme)
        form.run
        form["value"]
      end

      def current_theme
        # TODO: Integrate with ZettelHub theme system
        Huh::Themes.charm
      end
    end
  end
end
```

3. Update `lib/prompt_executor.rb` to use `UI::Prompt` with fallback:

```ruby
# lib/prompt_executor.rb
module PromptExecutor
  def self.execute(prompt_def, config, vars = {})
    if huh_available?
      execute_with_huh(prompt_def, config, vars)
    elsif gum_available?
      execute_with_gum(prompt_def, config, vars)
    else
      execute_with_stdin(prompt_def, config, vars)
    end
  end

  def self.huh_available?
    @huh_available ||= begin
      require "huh"
      true
    rescue LoadError
      false
    end
  end

  def self.execute_with_huh(prompt_def, config, vars)
    type = prompt_def['type']&.downcase || 'input'
    label = prompt_def['prompt'] || prompt_def['label'] || "Enter #{prompt_def['key']}"
    default = resolve_default(prompt_def['default'], vars)
    options = resolve_options(prompt_def, config, vars)
    multi = prompt_def['multi'] == true

    case type
    when 'input'
      UI::Prompt.input(label, default: default, required: prompt_def['required'])
    when 'write'
      UI::Prompt.write(label, default: default)
    when 'choose'
      multi ? UI::Prompt.multi_select(label, options) : UI::Prompt.select(label, options)
    when 'filter'
      multi ? UI::Prompt.multi_select(label, options) : UI::Prompt.filter(label, options)
    when 'confirm'
      UI::Prompt.confirm(label, default: default)
    else
      UI::Prompt.input(label, default: default)
    end
  end
end
```

### Phase 4: Interactive Pickers (Higher Risk)

**Goal**: Replace `fzf` with `bubbletea` + `bubbles`

This is the most complex phase. Options:

1. **Keep fzf**: It's fast, well-tested, and users expect it
2. **Hybrid**: Use bubbles for simple lists, fzf for large datasets
3. **Full replacement**: Build custom fuzzy picker with bubbletea

If replacing fzf, need to implement:
- Fuzzy matching algorithm
- Keyboard navigation
- Preview pane integration
- Multi-select support

```ruby
# lib/ui/picker.rb
require "bubbletea"
require "bubbles"

module UI
  class Picker
    def self.pick(items, prompt: "Select", preview: nil, multi: false)
      # Implementation with bubbletea + bubbles
      # Or fallback to fzf
    end
  end
end
```

**Recommendation**: Keep `fzf` for Phase 4 unless there's a compelling reason to replace it. The bubbles List component may not match fzf's performance and feature set.

## Theme Integration

Map ZettelHub themes to Charm Ruby styles:

```ruby
# lib/ui/theme.rb
require "huh"
require "lipgloss"

module UI
  class Theme
    def self.huh_theme(zh_theme)
      palette = zh_theme['palette'] || {}

      Huh::Theme.new.tap do |t|
        t.focused.title = Lipgloss::Style.new
          .foreground(palette['accent'] || "#88C0D0")
          .bold(true)

        t.focused.selected_option = Lipgloss::Style.new
          .foreground(palette['accent_secondary'] || "#81A1C1")

        t.focused.unselected_option = Lipgloss::Style.new
          .foreground(palette['text_muted'] || "#4C566A")

        # Map other styles...
      end
    end

    def self.glamour_style(zh_theme)
      # Map to glamour style name or custom JSON
      case zh_theme['name']
      when 'dracula' then 'dracula'
      when 'light' then 'light'
      else 'dark'
      end
    end

    def self.lipgloss_colors(zh_theme)
      palette = zh_theme['palette'] || {}
      {
        accent: palette['accent'] || "#88C0D0",
        accent_secondary: palette['accent_secondary'] || "#81A1C1",
        border: palette['border'] || "#4C566A",
        text: palette['text'] || "#ECEFF4",
        text_muted: palette['text_muted'] || "#4C566A"
      }
    end
  end
end
```

## Benefits

1. **Fewer external dependencies** - No need to install gum, glow separately
2. **Consistent theming** - Single theme system across all UI components
3. **Better error handling** - Ruby exceptions vs subprocess exit codes
4. **Testable** - Can mock prompts in unit tests
5. **Cross-platform** - Ruby handles platform differences
6. **Bundled distribution** - Could ship as self-contained gem

## Challenges

1. **C extensions** - Some Charm Ruby gems use Go shared libraries
2. **Maturity** - Newer ports, less battle-tested than originals
3. **Performance** - May be slower for large datasets (keep fzf/ripgrep)
4. **Fuzzy filtering** - No direct fzf replacement with same UX

## Implementation Order

1. ✅ Add gems to Gemfile (development/optional)
2. Create `lib/ui/` module with wrappers
3. Migrate `glamour` for markdown preview
4. Migrate `huh` for prompts (biggest improvement)
5. Migrate `lipgloss` for tables/styling
6. Evaluate `bubbles` for fzf replacement (may keep fzf)
7. Keep `ripgrep` for search (no Ruby replacement)

## Testing Strategy

With native Ruby libraries, prompts become testable:

```ruby
# test/ui/prompt_test.rb
class PromptTest < Minitest::Test
  def test_input_returns_value
    # Mock huh form
    UI::Prompt.stub(:run_form, "test value") do
      result = UI::Prompt.input("Enter name")
      assert_equal "test value", result
    end
  end

  def test_confirm_returns_boolean
    UI::Prompt.stub(:run_form, true) do
      result = UI::Prompt.confirm("Continue?")
      assert_equal true, result
    end
  end
end
```

## References

- [Charm Ruby](https://charm-ruby.dev/) - Main documentation
- [huh-ruby](https://github.com/marcoroth/huh-ruby) - Forms library
- [glamour-ruby](https://github.com/marcoroth/glamour-ruby) - Markdown rendering
- [lipgloss-ruby](https://github.com/marcoroth/lipgloss-ruby) - Styling
- [bubbletea-ruby](https://github.com/marcoroth/bubbletea-ruby) - TUI framework
- [bubbles-ruby](https://github.com/marcoroth/bubbles-ruby) - TUI components
