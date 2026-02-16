# ZettelHub Template System

This document provides comprehensive documentation for the ZettelHub templating system, including template structure, variables, dynamic prompts, and configuration options.

## Table of Contents

- [Overview](#overview)
- [Template Structure](#template-structure)
- [Template Discovery](#template-discovery)
- [Template Variables](#template-variables)
  - [Built-in Variables](#built-in-variables)
  - [Time Variables](#time-variables)
  - [Custom Variables](#custom-variables)
- [The Config Section](#the-config-section)
  - [path](#path)
  - [default_alias](#default_alias)
  - [default_tags](#default_tags)
  - [prompts](#prompts)
- [Dynamic Prompts](#dynamic-prompts)
  - [Prompt Types](#prompt-types)
  - [Prompt Options](#prompt-options)
  - [Option Sources](#option-sources)
  - [Conditional Prompts](#conditional-prompts)
  - [Value Transformations](#value-transformations)
  - [Value Validation](#value-validation)
- [Helper Functions](#helper-functions)
- [YAML Quoting Rules](#yaml-quoting-rules)
- [Complete Examples](#complete-examples)

---

## Overview

ZettelHub uses ERB (Embedded Ruby) templates to generate notes. Templates define:

1. **Front matter** - YAML metadata for the note (id, type, title, tags, etc.)
2. **Config section** - Template-specific settings (output path, prompts, defaults)
3. **Body content** - The markdown content of the note

When you run `zh add <type>`, ZettelHub:

1. Finds the template matching the type
2. Collects values via interactive prompts (if defined)
3. Renders the template with all variables
4. Writes the note to the configured path
5. Opens the note in your editor

---

## Template Structure

A template file has three main sections:

```erb
---
# YAML Front Matter - becomes note metadata
id: "<%= id %>"
type: template_type
title: "<%= title %>"
tags: <%= tags %>
# ... other metadata fields

config:
    # Template configuration (removed from final output)
    path: "path/to/<%= id %>.md"
    prompts:
        - key: title
          type: input
          prompt: "Enter title"
---

# <%= title %>

Body content with ERB placeholders...

<%= content %>
```

### Sections Explained

| Section | Purpose | Included in Output |
|---------|---------|-------------------|
| Front matter | Note metadata (YAML) | Yes |
| `config:` block | Template settings, prompts | No (removed) |
| Body | Markdown content | Yes |

---

## Template Discovery

Templates are discovered automatically by scanning `.erb` files. No configuration listing is needed.

### Search Order (later overrides earlier)

1. **Bundled templates**: `~/.local/zh/lib/templates/`
2. **Global user templates**: `~/.config/zh/templates/`
3. **Local notebook templates**: `.zh/templates/` (within notebook)

### Type Detection

The template **type** is determined by the `type` field in the template's front matter:

```yaml
---
type: meeting  # This template handles "zh add meeting"
```

---

## Template Variables

### Built-in Variables

These variables are always available in templates:

| Variable | Description | Example |
|----------|-------------|---------|
| `id` | Unique 8-character hex ID | `a1b2c3d4` |
| `type` | Note type from template | `note` |
| `title` | Note title (from CLI or prompt) | `My Note` |
| `tags` | Array of tags | `["work", "todo"]` |
| `description` | Optional description | `A brief overview` |
| `aliases` | Note aliases | `note> 2026-02-16: My Note` |
| `content` | Body content (for imports) | `...` |

### Time Variables

All time-related variables based on current date/time:

| Variable | Format | Example |
|----------|--------|---------|
| `date` | `YYYY-MM-DD` | `2026-02-16` |
| `year` | `YYYY` | `2026` |
| `month` | `MM` | `02` |
| `day` | `DD` | `16` |
| `week` | `WW` (ISO week) | `07` |
| `week_year` | `YYYY` (ISO week year) | `2026` |
| `month_name` | Full month name | `February` |
| `month_name_short` | Abbreviated month | `Feb` |
| `day_name` | Full day name | `Monday` |
| `day_name_short` | Abbreviated day | `Mon` |
| `time` | `HH:MM` | `14:30` |
| `time_iso` | `HH:MM:SS` | `14:30:45` |
| `hour` | `HH` | `14` |
| `minute` | `MM` | `30` |
| `second` | `SS` | `45` |
| `timestamp` | `YYYYMMDDHHmmss` | `20260216143045` |

### Custom Variables

You can define custom variables in the front matter that reference other variables:

```yaml
---
id: "<%= id %>"
type: meeting
title: "<%= title %>"
meeting_slug: "<%= slugify(title) %>"  # Custom variable
filename: "<%= id %>-<%= meeting_slug %>"  # References custom var
config:
    path: "meetings/<%= filename %>.md"
---
```

**Dependency Resolution**: Custom variables are resolved in dependency order. If `filename` depends on `meeting_slug`, `meeting_slug` is resolved first.

---

## The Config Section

The `config:` block contains template-specific settings that are **not** written to the output file.

### path

Defines the output file path relative to the notebook root.

```yaml
config:
    path: "<%= id %>-<%= slugify(title) %>.md"
```

**Path Examples**:

```yaml
# Simple flat structure
path: "<%= id %>.md"

# Organized by type
path: "notes/<%= slugify(title) %>-<%= id %>.md"

# Organized by date
path: "journal/<%= year %>/<%= date %>.md"

# Nested by year and month
path: "meetings/<%= year %>/<%= month %>/<%= id %>-<%= slugify(title) %>.md"

# Using week numbers
path: "journal/<%= year %>/w<%= week %>.md"
```

### default_alias

Pattern for generating the default alias. Placeholders use `{field}` syntax:

```yaml
config:
    default_alias: "{type}> {date}: {title}"
```

Available placeholders: `{type}`, `{date}`, `{title}`, `{id}`

### default_tags

Tags automatically added to every note created with this template:

```yaml
config:
    default_tags:
        - meeting
        - work
```

These merge with user-supplied tags (defaults first, then user tags, duplicates removed).

### prompts

Array of interactive prompt definitions. See [Dynamic Prompts](#dynamic-prompts).

---

## Dynamic Prompts

Prompts allow templates to collect user input interactively when creating notes.

### Prompt Types

#### `input` - Single-line text input

```yaml
- key: title
  type: input
  prompt: "Enter title"
  required: true
  default: "Untitled"
```

#### `write` - Multi-line text input

```yaml
- key: notes
  type: write
  prompt: "Enter notes (empty line to finish)"
```

#### `choose` - Select from options

```yaml
- key: priority
  type: choose
  prompt: "Select priority"
  options:
      - high
      - medium
      - low
  default: medium
```

#### `filter` - Fuzzy search selection

```yaml
- key: account
  type: filter
  prompt: "Select account"
  source:
      type: notes
      filter_type: account
      return: wikilink
```

#### `confirm` - Yes/No confirmation

```yaml
- key: is_urgent
  type: confirm
  prompt: "Is this urgent?"
  default: false
```

### Prompt Options

| Option | Type | Description |
|--------|------|-------------|
| `key` | string | Variable name (required) |
| `type` | string | Prompt type: `input`, `write`, `choose`, `filter`, `confirm` |
| `prompt` | string | Display text shown to user |
| `required` | boolean | If true, value cannot be empty |
| `optional` | boolean | If true, asks "Add X?" confirmation first |
| `multi` | boolean | For `choose`/`filter`: allow multiple selections |
| `default` | any | Default value if user provides none |
| `options` | array | Static options for `choose`/`filter` |
| `source` | object | Dynamic options source (see below) |
| `when` | string | Condition expression (see below) |
| `hidden` | boolean | If true, prompt is skipped (uses default) |
| `transform` | array | Value transformations to apply |
| `validate` | object | Validation rules |
| `allow_new` | boolean | For `filter`: allow custom value if no match |

### Multi-Select Prompts

Add `multi: true` to allow selecting multiple items:

```yaml
- key: attendees
  type: filter
  prompt: "Select attendees"
  multi: true
  source:
      type: notes
      filter_type: person
      return: wikilink
```

The result is an array that can be iterated in the template:

```erb
<% attendees.each do |person| %>
- <%= person %>
<% end %>
```

### Optional Prompts

Add `optional: true` to prompt for confirmation before collecting the value:

```yaml
- key: birthday
  type: input
  prompt: "Birthday (YYYY-MM-DD)"
  optional: true
```

The user will see: "Add Birthday (YYYY-MM-DD)? [y/N]"

### Option Sources

Dynamic sources for `choose` and `filter` prompts:

#### `tags` - Tags from the index

```yaml
source:
    type: tags
    sort: count  # Sort by usage count (most used first)
```

#### `notes` - Notes from the index

```yaml
source:
    type: notes
    filter_type: person           # Filter by note type
    return: wikilink              # Return format
    sort: alpha                   # Sort alphabetically
```

**Filter type** supports multiple types with `|`:

```yaml
filter_type: "organization|account"  # Match either type
```

**Return formats**:

| Value | Output | Example |
|-------|--------|---------|
| `title` | Note title | `John Smith` |
| `id` | Note ID | `a1b2c3d4` |
| `wikilink` | Wikilink format | `[[a1b2c3d4\|John Smith]]` |
| `path` | File path | `people/john-smith-a1b2c3d4.md` |
| `field` | Custom field | (use with `field: fieldname`) |

#### `files` - Files from filesystem

```yaml
source:
    type: files
    glob: "**/*.md"
    base: "/path/to/dir"
    return: relative  # or: basename, full path
```

#### `command` - External command output

```yaml
source:
    type: command
    command: "cat /path/to/options.txt"
```

### Conditional Prompts

Show prompts only when conditions are met using the `when` option:

```yaml
# Only show if type is 'project'
- key: deadline
  type: input
  prompt: "Project deadline"
  when: "type == 'project'"

# Only show if account was selected
- key: contact
  type: filter
  prompt: "Primary contact"
  when: "account?"

# Compound conditions
- key: budget
  type: input
  prompt: "Budget amount"
  when: "type == 'project' && is_urgent?"
```

**Condition Syntax**:

| Pattern | Meaning | Example |
|---------|---------|---------|
| `var?` | Variable is truthy | `account?` |
| `var == 'value'` | Equality | `type == 'meeting'` |
| `var != 'value'` | Inequality | `status != 'done'` |
| `var =~ /pattern/` | Regex match | `title =~ /urgent/i` |
| `var in ['a', 'b']` | List membership | `type in ['note', 'meeting']` |
| `cond1 && cond2` | AND | `type == 'meeting' && urgent?` |
| `cond1 \|\| cond2` | OR | `type == 'note' \|\| type == 'idea'` |

### Value Transformations

Transform user input before storing:

```yaml
- key: emails
  type: input
  prompt: "Email(s), comma-separated"
  transform:
      - { split: "," }  # Split into array
```

**Available Transforms**:

| Transform | Description | Example |
|-----------|-------------|---------|
| `trim` | Remove whitespace | `"  text  "` → `"text"` |
| `lowercase` | Convert to lowercase | `"TEXT"` → `"text"` |
| `uppercase` | Convert to uppercase | `"text"` → `"TEXT"` |
| `capitalize` | Capitalize first letter | `"text"` → `"Text"` |
| `titleize` | Capitalize each word | `"hello world"` → `"Hello World"` |
| `slugify` | URL-safe slug | `"Hello World!"` → `"hello-world"` |
| `{ split: "," }` | Split to array | `"a,b,c"` → `["a","b","c"]` |
| `{ join: ", " }` | Join array | `["a","b"]` → `"a, b"` |
| `{ replace: [pat, rep] }` | Replace pattern | `"foo"` → `"bar"` |
| `{ prepend: "prefix" }` | Add prefix | `"text"` → `"prefix text"` |
| `{ append: "suffix" }` | Add suffix | `"text"` → `"text suffix"` |
| `{ default: "value" }` | Default if empty | `""` → `"value"` |
| `{ truncate: 50 }` | Limit length | Truncates to 50 chars |
| `strip_prefix:X` | Remove prefix | `"pre_text"` → `"text"` |
| `strip_suffix:X` | Remove suffix | `"text_suf"` → `"text"` |

**Chaining Transforms**:

```yaml
transform:
    - trim
    - lowercase
    - { split: "," }
```

### Value Validation

Validate user input with rules:

```yaml
- key: email
  type: input
  prompt: "Email address"
  validate:
      type: email
      message: "Please enter a valid email"

- key: url
  type: input
  prompt: "Website URL"
  validate:
      type: url

- key: code
  type: input
  prompt: "Project code"
  validate:
      pattern: "^[A-Z]{3}-[0-9]{4}$"
      message: "Format: ABC-1234"
      min_length: 8
      max_length: 8
```

**Built-in Validation Types**:

| Type | Description |
|------|-------------|
| `url` | Valid HTTP/HTTPS URL |
| `email` | Valid email address |
| `date` | Parseable date |
| `id` | 6-12 hex characters |
| `slug` | Lowercase alphanumeric with hyphens |
| `alphanumeric` | Letters and numbers only |
| `numeric` | Numbers only |

**Validation Options**:

| Option | Description |
|--------|-------------|
| `type` | Built-in validator name |
| `pattern` | Custom regex pattern |
| `min_length` | Minimum string length |
| `max_length` | Maximum string length |
| `required` | Shorthand for non-empty check |
| `message` | Custom error message |

---

## Helper Functions

### `slugify(text)`

Converts text to a URL-safe slug:

```erb
<%= slugify("Hello World!") %>  <!-- Output: hello-world -->
<%= slugify("Meeting: Q1 Review") %>  <!-- Output: meeting-q1-review -->
```

Use in paths:

```yaml
config:
    path: "notes/<%= slugify(title) %>-<%= id %>.md"
```

---

## YAML Quoting Rules

**Critical**: Follow these rules to prevent YAML parsing errors.

### Always Quote

String values that may contain special YAML characters (`: # [ ] & * ! | > ' " % @ \``):

```yaml
# ✓ Correct
title: "<%= title %>"
id: "<%= id %>"
config:
    path: "<%= id %>-<%= slugify(title) %>.md"
```

### Never Quote

The `tags` field (rendered as YAML array):

```yaml
# ✓ Correct
tags: <%= tags %>

# ✗ Wrong - would store as string, not array
tags: "<%= tags %>"
```

### Why It Matters

Unquoted values with special characters cause parsing errors:

```yaml
# ✗ Will fail if title contains ":"
title: <%= title %>

# User enters: "Meeting: Q1 Review"
# YAML sees: title: Meeting: Q1 Review
# Error: "did not find expected key while parsing a block mapping"
```

---

## Complete Examples

### Simple Note Template

```erb
---
id: "<%= id %>"
type: note
date: "<%= date %>"
title: "<%= title %>"
aliases: "<%= aliases %>"
tags: <%= tags %>
description: "<%= description %>"
config:
    path: "<%= id %>-<%= slugify(title) %>.md"
    default_alias: "{type}> {date}: {title}"
    default_tags: []
---

# <%= title %>

<%= content %>
```

### Meeting Template with Dynamic Prompts

```erb
---
id: "<%= id %>"
type: meeting
date: "<%= date %>"
title: "<%= title %>"
aliases: "<%= aliases %>"
tags: <%= tags %>
attendees: <%= attendees %>
account: "<%= account %>"
config:
    path: "meetings/<%= year %>/<%= month %>/<%= id %>-<%= slugify(title) %>.md"
    default_alias: "{type}> {date}: {title}"
    default_tags:
        - meeting
    prompts:
        - key: title
          type: input
          prompt: "Meeting title"
          required: true
        - key: account
          type: filter
          prompt: "Related account"
          optional: true
          source:
              type: notes
              filter_type: account
              return: wikilink
        - key: attendees
          type: filter
          prompt: "Attendees"
          optional: true
          multi: true
          source:
              type: notes
              filter_type: person
              return: wikilink
---

# Meeting: <%= title %>

**Date:** <%= date %>
<% if account && !account.to_s.empty? %>
**Account:** <%= account %>
<% end %>

## Attendees

<% if attendees.is_a?(Array) && attendees.any? %>
<% attendees.each do |person| %>
- <%= person %>
<% end %>
<% end %>

## Agenda

## Notes

## Action Items
```

### Person Template with Transforms

```erb
---
id: "<%= id %>"
type: person
date: "<%= date %>"
title: "<%= full_name %>"
full_name: "<%= full_name %>"
aliases: ["person> <%= full_name %>", "@<%= full_name %>"]
tags: <%= tags %>
emails: <%= emails %>
organization: "<%= organization %>"
role: "<%= role %>"
config:
    path: "people/<%= slugify(full_name) %>-<%= id %>.md"
    default_tags: [contact, person]
    prompts:
        - key: full_name
          type: input
          prompt: "Full name"
          required: true
        - key: emails
          type: input
          prompt: "Email(s), comma-separated"
          optional: true
          transform:
              - { split: "," }
        - key: organization
          type: filter
          prompt: "Organization"
          optional: true
          source:
              type: notes
              filter_type: "organization|account"
              return: wikilink
        - key: role
          type: input
          prompt: "Role/Title"
          optional: true
---

# <%= full_name %>

## Contact Information

<% email_list = emails.is_a?(Array) ? emails : [emails].compact.reject(&:empty?) rescue [] %>
<% if email_list.any? %>
**Email**: <% email_list.each do |email| %>[<%= email %>](mailto:<%= email %>) <% end %>
<% end %>
<% unless organization.to_s.empty? %>
**Organization**: <%= organization %>
<% end %>
<% unless role.to_s.empty? %>
**Role**: <%= role %>
<% end %>

## Notes

<%= content %>
```

### Bookmark Template with Validation

```erb
---
id: "<%= id %>"
type: bookmark
date: "<%= date %>"
uri: "<%= uri %>"
title: "<%= title %>"
tags: <%= tags %>
description: "<%= description %>"
config:
    path: "bookmarks/<%= slugify(title) %>-<%= id %>.md"
    default_tags: [resource, bookmark]
    prompts:
        - key: uri
          type: input
          prompt: "URL"
          required: true
          validate:
              type: url
              message: "Please enter a valid URL (http:// or https://)"
        - key: title
          type: input
          prompt: "Title"
          required: true
        - key: description
          type: input
          prompt: "Notes"
          optional: true
---

# <%= title %>

Link: [<%= uri %>](<%= uri %>)

<%= description %>
```

### Weekly Journal Template

```erb
---
id: "<%= id %>"
type: journal
date: "<%= date %>"
title: "Week <%= week %>, <%= year %>"
aliases: ["journal> Week <%= week %> <%= year %>"]
tags: <%= tags %>
config:
    path: "journal/<%= year %>/w<%= week %>.md"
    default_tags: [journal, weekly]
---

# Week <%= week %>, <%= year %>

## Goals

## Monday (<%= day_name %>)

## Tuesday

## Wednesday

## Thursday

## Friday

## Reflections
```

### Project Template with Conditional Prompts

```erb
---
id: "<%= id %>"
type: project
date: "<%= date %>"
title: "<%= title %>"
status: "<%= status %>"
deadline: "<%= deadline %>"
budget: "<%= budget %>"
tags: <%= tags %>
config:
    path: "projects/<%= slugify(title) %>-<%= id %>.md"
    default_tags: [project]
    prompts:
        - key: title
          type: input
          prompt: "Project name"
          required: true
        - key: status
          type: choose
          prompt: "Status"
          options:
              - planning
              - active
              - on-hold
              - completed
          default: planning
        - key: deadline
          type: input
          prompt: "Deadline (YYYY-MM-DD)"
          optional: true
          when: "status in ['planning', 'active']"
          validate:
              type: date
        - key: budget
          type: input
          prompt: "Budget"
          optional: true
          when: "status == 'planning'"
---

# <%= title %>

**Status:** <%= status %>
<% unless deadline.to_s.empty? %>
**Deadline:** <%= deadline %>
<% end %>
<% unless budget.to_s.empty? %>
**Budget:** <%= budget %>
<% end %>

## Overview

## Tasks

## Notes
```

---

## Tips and Best Practices

1. **Start simple**: Begin with basic templates and add prompts as needed
2. **Use `optional: true`**: For fields that aren't always needed
3. **Use `multi: true`**: For fields that can have multiple values (attendees, tags)
4. **Quote strings**: Always quote ERB placeholders in YAML front matter
5. **Don't quote tags**: The `tags` field must remain unquoted
6. **Test with special characters**: Try titles like "Meeting: Q1 Review" to verify YAML parsing
7. **Use `slugify()`**: For file paths to ensure valid filenames
8. **Leverage sources**: Use dynamic sources to link notes (wikilinks)
9. **Validate input**: Add validation for URLs, emails, dates

---

## See Also

- [ARCHITECTURE.md](../ARCHITECTURE.md) - System architecture
- [AGENTS.md](../AGENTS.md) - Development guidelines
- [README.md](../README.md) - Getting started
