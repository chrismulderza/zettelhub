# ZettelHub Enhancements Plan

Comprehensive plan covering template system enhancements, contact management, tag improvements, and editor integration.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Foundation: Template System](#2-foundation-template-system)
3. [Contact Management](#3-contact-management)
4. [Tag System Enhancements](#4-tag-system-enhancements)
5. [Editor Integration: Neovim](#5-editor-integration-neovim)
6. [Implementation](#6-implementation)
7. [Configuration Reference](#7-configuration-reference)

---

## 1. Overview

### 1.1 Goals

1. **Flexible Templates** - Custom variables and interactive prompts in templates
2. **Contact Management** - People, organizations, and accounts as atomic notes
3. **Organization Hierarchy** - Parent/subsidiary relationships via wikilinks
4. **Enhanced Tags** - Body hashtag extraction and improved tag queries
5. **Editor Integration** - Seamless Neovim completion and pickers

### 1.2 Design Principles

1. **Models are minimal** - Domain-specific fields live in templates, not hardcoded in models
2. **Templates define semantics** - Custom fields handled via dynamic template variables
3. **Prompts collect input** - Interactive field collection via `config.prompts`
4. **Hierarchy via wikilinks** - Parent/child relationships use existing link infrastructure
5. **Tags from anywhere** - Front matter and body hashtags unified

### 1.3 Feature Dependencies

```
┌─────────────────────────────────────────────────────────────────┐
│                    Template Variables                            │
│                         (Phase 1)                                │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Dynamic Prompts                               │
│                         (Phase 2)                                │
└─────────────────────────┬───────────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
┌─────────────────┐ ┌───────────┐ ┌─────────────────┐
│ Contact Mgmt    │ │ Tag       │ │ Neovim          │
│ (Phase 3-5)     │ │ (Phase 6) │ │ (Phase 7)       │
└─────────────────┘ └───────────┘ └─────────────────┘
```

---

## 2. Foundation: Template System

### 2.1 Template Variables

Expose any key defined in a template's YAML front matter to the ERB rendering context, allowing templates to define custom variables that can reference each other.

#### Example

```yaml
---
id: "<%= id %>"
type: note
project: "Alpha"
note_prefix: "<%= project %>-<%= type %>"
title: "<%= note_prefix %>: <%= title %>"
config:
    path: "projects/<%= project %>/<%= note_prefix %>-<%= id %>.md"
---
```

With `--title "Meeting notes"`, resolves to:
- `project` → `"Alpha"`
- `note_prefix` → `"Alpha-note"`
- `title` → `"Alpha-note: Meeting notes"`

#### Implementation

**File:** `lib/template_vars.rb`

**Components:**
1. `extract_custom_keys(frontmatter)` - Returns hash of non-standard keys
2. `detect_dependencies(value)` - Parses ERB to find variable references
3. `build_dependency_graph(custom_keys)` - Creates adjacency list
4. `topological_sort(graph)` - Returns ordered list (or raises on cycle)
5. `resolve_custom_vars(custom_keys, base_vars)` - Renders in dependency order

**Constants:**
```ruby
STANDARD_FRONTMATTER_KEYS = %w[id type date title aliases tags description config content].freeze
TIME_VAR_KEYS = %w[date year month week week_year month_name month_name_short 
                   day_name day_name_short time time_iso hour minute second timestamp id].freeze
STANDARD_CONFIG_KEYS = %w[path default_alias default_tags prompts].freeze
```

**Precedence (later wins):**
```ruby
vars = {}
vars.merge!(resolved_custom_vars)  # Template defaults (lowest)
vars.merge!(time_vars)              # Time variables
vars['type'] = type
vars['title'] = title unless title.to_s.empty?
vars['tags'] = format_tags_for_yaml(tags) unless tags.empty?
```

**Error Handling:**
- `TemplateVars::CyclicDependencyError` - Cycle detected in variable dependencies
- `TemplateVars::UndefinedVariableError` - Reference to non-existent variable

### 2.2 Dynamic Prompts

Templates define what inputs they need via `config.prompts`. Interactive collection with multiple prompt types and dynamic option sources.

#### Example

```yaml
---
id: "<%= id %>"
type: client-meeting
title: "<%= title %>"
client: "<%= client %>"
billable: <%= billable %>
config:
    path: "clients/<%= slugify(client) %>/meetings/<%= date %>-<%= id %>.md"
    prompts:
      - key: title
        type: input
        placeholder: "Meeting title"
        required: true
      - key: client
        type: filter
        source: { type: tags, filter: "^client-" }
        required: true
      - key: billable
        type: confirm
        placeholder: "Is this billable?"
        when: "client?"
---
```

#### Prompt Types

| Type | Gum Command | Fallback | Description |
|------|-------------|----------|-------------|
| `input` | `gum input` | `print; gets` | Single-line text |
| `write` | `gum write` | Multi-line stdin | Multi-line text |
| `choose` | `gum choose` | Numbered list | Select from options |
| `filter` | `gum filter` | Numbered list | Fuzzy search options |
| `confirm` | `gum confirm` | `gets =~ /^y/i` | Yes/no |

#### Option Sources

```yaml
source:
  type: tags|notes|files|command
  filter: "regex"              # Filter pattern
  transform: "strip_prefix:x"  # Value transformation
  sort: alpha|count|recent     # Sort order
  limit: 20                    # Max results
  allow_new: true              # Allow custom value (filter type)
```

**Source Types:**
- `tags` - From indexed tags
- `notes` - From indexed notes (with `filter_type`, `field`, `return`)
- `files` - From filesystem glob
- `command` - From external command output

#### Conditions

| Operator | Example | Description |
|----------|---------|-------------|
| `==` | `type == 'meeting'` | Equality |
| `!=` | `status != 'draft'` | Inequality |
| `=~` | `title =~ /^WIP/` | Regex match |
| `in` | `type in ['a', 'b']` | List membership |
| `&&` | `a == 'x' && b == 'y'` | Logical AND |
| `\|\|` | `a == 'x' \|\| a == 'y'` | Logical OR |
| `?` | `project?` | Truthy (non-nil, non-empty) |

#### Transformations

| Transform | Input | Output |
|-----------|-------|--------|
| `trim` | `"  hello  "` | `"hello"` |
| `lowercase` | `"Hello"` | `"hello"` |
| `slugify` | `"Hello World"` | `"hello-world"` |
| `{ split: "," }` | `"a, b, c"` | `["a", "b", "c"]` |
| `{ join: ", " }` | `["a", "b"]` | `"a, b"` |

#### Validation

```yaml
validate:
  type: url|email|date|id|slug  # Built-in validator
  # OR
  pattern: "^[A-Z]{2}-\\d{4}$"  # Custom regex
  message: "Error message"       # Custom error
```

#### Implementation Files

| File | Purpose |
|------|---------|
| `lib/prompt_executor.rb` | Execute prompts by type |
| `lib/prompt_collector.rb` | Collect values with conditions |
| `lib/option_source.rb` | Resolve dynamic options |
| `lib/condition_evaluator.rb` | Evaluate condition expressions |
| `lib/value_transformer.rb` | Apply transformations |
| `lib/value_validator.rb` | Validate values |

---

## 3. Contact Management

### 3.1 Models

Models provide file-based initialization and minimal accessors. Domain-specific metadata lives in templates.

#### `lib/models/person.rb`

```ruby
# frozen_string_literal: true

require_relative 'document'
require_relative '../utils'

# Person resource: contact information from metadata.
class Person < Document
  def initialize(opts = {})
    path = opts[:path] || opts['path']
    raise ArgumentError, 'path is required' unless path

    file_content = File.read(path)
    metadata, body = Utils.parse_front_matter(file_content)
    metadata = (opts[:metadata] || opts['metadata'] || {}).merge(metadata)

    document_opts = {
      id: opts[:id] || opts['id'] || metadata['id']&.to_s || Document.generate_id,
      path: path,
      title: opts[:title] || opts['title'] || metadata['title'],
      type: opts[:type] || opts['type'] || metadata['type'],
      date: opts[:date] || opts['date'] || metadata['date'],
      content: body,
      metadata: metadata,
      body: body
    }

    super(document_opts)
  end

  def full_name
    metadata['full_name'] || metadata[:full_name] || title
  end

  def emails
    Array(metadata['emails'] || metadata[:emails])
  end

  def phones
    Array(metadata['phones'] || metadata[:phones])
  end

  def organization
    metadata['organization'] || metadata[:organization]
  end
end
```

#### `lib/models/organization.rb`

```ruby
# frozen_string_literal: true

require_relative 'document'
require_relative '../utils'

# Organization resource: base class for companies, institutions, groups.
class Organization < Document
  def initialize(opts = {})
    path = opts[:path] || opts['path']
    raise ArgumentError, 'path is required' unless path

    file_content = File.read(path)
    metadata, body = Utils.parse_front_matter(file_content)
    metadata = (opts[:metadata] || opts['metadata'] || {}).merge(metadata)

    document_opts = {
      id: opts[:id] || opts['id'] || metadata['id']&.to_s || Document.generate_id,
      path: path,
      title: opts[:title] || opts['title'] || metadata['title'],
      type: opts[:type] || opts['type'] || metadata['type'],
      date: opts[:date] || opts['date'] || metadata['date'],
      content: body,
      metadata: metadata,
      body: body
    }

    super(document_opts)
  end

  def name
    metadata['name'] || metadata[:name] || title
  end

  def website
    metadata['website'] || metadata[:website]
  end

  def parent
    metadata['parent'] || metadata[:parent]
  end

  def subsidiaries
    Array(metadata['subsidiaries'] || metadata[:subsidiaries])
  end
end
```

#### `lib/models/account.rb`

```ruby
# frozen_string_literal: true

require_relative 'organization'

# Account: customer organization tracked in external systems.
# CRM-specific fields are template-defined metadata.
class Account < Organization
  # Access CRM data via: account.metadata['crm']['segment'], etc.
end
```

#### Model Factory

```ruby
# In lib/utils.rb
def self.model_for_type(type)
  case type
  when 'person' then Person
  when 'organization' then Organization
  when 'account' then Account
  when 'bookmark' then Bookmark
  when 'journal' then Journal
  when 'meeting' then Meeting
  else Note
  end
end
```

### 3.2 Templates

#### `lib/templates/person.erb`

```erb
---
id: "<%= id %>"
type: person
date: "<%= date %>"
title: "<%= title %>"
full_name: "<%= full_name %>"
aliases: <%= aliases %>
tags: <%= tags %>
emails: <%= emails %>
phones: <%= phones %>
organization: "<%= organization %>"
role: "<%= role %>"
birthday: "<%= birthday %>"
address: "<%= address %>"
website: "<%= website %>"
social:
  linkedin: "<%= linkedin %>"
  github: "<%= github %>"
  twitter: "<%= twitter %>"
relationships: <%= relationships %>
last_contact: "<%= last_contact %>"
config:
  path: "people/<%= slugify(full_name) %>-<%= id %>.md"
  default_tags: [contact, person]
  prompts:
    - key: full_name
      type: input
      placeholder: "Full name"
      required: true
    - key: email
      type: input
      placeholder: "Email address"
    - key: organization
      type: filter
      placeholder: "Organization (optional)"
      source:
        type: notes
        filter_type: "organization|account"
        return: wikilink
---

# <%= title %>

## Contact Information

<% unless emails.nil? || emails.empty? -%>
**Email**: <% Array(emails).each do |email| %>[<%= email %>](mailto:<%= email %>) <% end %>
<% end -%>
<% unless phones.nil? || phones.empty? -%>
**Phone**: <% Array(phones).each do |phone| %>[<%= phone %>](tel:<%= phone.to_s.gsub(/\s/, '') %>) <% end %>
<% end -%>
<% unless organization.to_s.empty? -%>
**Organization**: <%= organization %>
<% end -%>
<% unless role.to_s.empty? -%>
**Role**: <%= role %>
<% end -%>

## Notes

<%= content %>
```

**Alias Generation:** Two aliases are generated:
```yaml
aliases: ["person> Jane Doe", "@Jane Doe"]
```

The `@Name` alias enables concise references: `[[@Jane Doe]]`

#### `lib/templates/organization.erb`

```erb
---
id: "<%= id %>"
type: organization
date: "<%= date %>"
title: "<%= title %>"
name: "<%= name %>"
aliases: <%= aliases %>
tags: <%= tags %>
website: "<%= website %>"
industry: "<%= industry %>"
address: "<%= address %>"
parent: "<%= parent %>"
subsidiaries: <%= subsidiaries %>
config:
  path: "organizations/<%= slugify(name) %>-<%= id %>.md"
  default_tags: [organization]
  prompts:
    - key: title
      type: input
      placeholder: "Organization name"
      required: true
    - key: website
      type: input
      placeholder: "Website URL (optional)"
    - key: parent
      type: filter
      placeholder: "Parent organization (optional)"
      source:
        type: notes
        filter_type: "organization|account"
        return: wikilink
---

# <%= title %>

## Organization Information

<% unless website.to_s.empty? -%>
**Website**: [<%= website %>](<%= website %>)
<% end -%>
<% unless parent.to_s.empty? -%>
**Parent**: <%= parent %>
<% end -%>

## Subsidiaries

## Notes

<%= content %>
```

#### Account Template (User-defined)

Account templates are user-defined in `.zh/templates/` with CRM-specific fields:

```erb
---
id: "<%= id %>"
type: account
title: "<%= title %>"
name: "<%= title %>"
parent: "<%= parent %>"
subsidiaries: <%= subsidiaries %>
crm:
    segment: "<%= crm_segment %>"
    territory: "<%= crm_territory %>"
    owner: "<%= crm_owner %>"
config:
    path: "accounts/<%= slugify(title) %>-<%= id %>.md"
    default_tags: [account, organization]
    prompts:
      - key: title
        type: input
        placeholder: "Account name"
        required: true
      - key: crm_segment
        type: choose
        options: ["Enterprise", "Commercial", "SMB"]
      - key: crm_owner
        type: input
        placeholder: "Account owner"
---
```

CRM fields are template-defined, not model methods. Access via `metadata['crm']['segment']`.

### 3.3 Commands

#### Person Command (`lib/cmd/person.rb`)

| Subcommand | Description |
|------------|-------------|
| `zh person` | Interactive browser (fzf) |
| `zh person add [NAME]` | Create new contact |
| `zh person list` | Compact tabular list |
| `zh person import FILE` | Import from vCard/CSV |
| `zh person export` | Export to vCard |
| `zh person birthdays` | Upcoming birthdays |
| `zh person stale` | Contacts not recently interacted with |
| `zh person merge ID1 ID2` | Merge duplicate contacts |

#### Organization Command (`lib/cmd/org.rb`)

| Subcommand | Description |
|------------|-------------|
| `zh org` | Interactive browser |
| `zh org tree ID` | Display hierarchy tree |
| `zh org parent ID` | Show parent organization |
| `zh org subs ID` | List direct subsidiaries |
| `zh org ancestors ID` | List all ancestors |
| `zh org descendants ID` | List all descendants |

### 3.4 Organization Hierarchy

Organizations and accounts support parent-child relationships via wikilinks.

#### Hierarchy Fields

```yaml
# Parent company
parent: null
subsidiaries:
  - "[[def456|Discovery Health Ltd]]"
  - "[[ghi789|Discovery Life Ltd]]"

# Subsidiary
parent: "[[abc123|Discovery Ltd]]"
subsidiaries: []
```

#### Hierarchy Utility Methods

Add to `lib/utils.rb`:

```ruby
module Utils
  # Extracts note ID from wikilink "[[id|title]]" or "[[id]]"
  def self.extract_id_from_wikilink(wikilink)
    return nil if wikilink.to_s.empty?
    match = wikilink.match(/\[\[([^\]|]+)/)
    match ? match[1] : nil
  end

  def self.parent_org_id(note)
    extract_id_from_wikilink(note.metadata['parent'])
  end

  def self.subsidiary_ids(note)
    Array(note.metadata['subsidiaries']).map { |link| extract_id_from_wikilink(link) }.compact
  end

  def self.ancestor_ids(note, db)
    ancestors = []
    current_id = parent_org_id(note)
    while current_id
      ancestors << current_id
      parent_note = load_note_by_id(db, current_id)
      break unless parent_note
      current_id = parent_org_id(parent_note)
    end
    ancestors
  end

  def self.descendant_ids(note, db)
    descendants = []
    queue = subsidiary_ids(note)
    while queue.any?
      child_id = queue.shift
      descendants << child_id
      child_note = load_note_by_id(db, child_id)
      next unless child_note
      queue.concat(subsidiary_ids(child_note))
    end
    descendants
  end
end
```

#### Tree Display

```bash
zh org tree abc123

Discovery Ltd (abc123)
├── Discovery Health Ltd (def456)
│   └── Discovery Health Medical Scheme (jkl012)
├── Discovery Life Ltd (ghi789)
└── Discovery Insure Ltd (mno345)
```

### 3.5 VCF/vCard Interoperability

#### Property Mapping

| vCard Property | ZettelHub Metadata |
|----------------|-------------------|
| `FN` | `full_name`, `title` |
| `N` | Parsed into `full_name` |
| `EMAIL` | `emails[]` |
| `TEL` | `phones[]` |
| `ORG` | `organization` |
| `TITLE` | `role` |
| `BDAY` | `birthday` |
| `ADR` | `address` |
| `URL` | `website` |
| `NOTE` | Body content |
| `X-SOCIALPROFILE` | `social.*` |

#### Import

```bash
zh person import contacts.vcf
zh person import --format csv google-contacts.csv
zh person import --dry-run --check-duplicates contacts.vcf
```

#### Export

```bash
zh person export --output contacts.vcf
zh person export --tag work --format vcf4
```

---

## 4. Tag System Enhancements

### 4.1 Hashtag Extraction

Extract hashtags (`#tagname`) from note body during indexing.

#### Schema

```sql
CREATE TABLE IF NOT EXISTS body_tags (
  note_id TEXT NOT NULL,
  tag TEXT NOT NULL,
  PRIMARY KEY (note_id, tag)
);
CREATE INDEX idx_body_tags_tag ON body_tags(tag);
CREATE INDEX idx_body_tags_note ON body_tags(note_id);
```

#### Extraction Pattern

```ruby
# Match #tag but not inside code blocks or URLs
HASHTAG_PATTERN = /(?<![&\w])#([a-zA-Z][a-zA-Z0-9_-]{1,49})(?![a-zA-Z0-9_-])/

def extract_body_hashtags(body)
  # Skip code blocks
  body_without_code = body.gsub(/```[\s\S]*?```/, '')
                          .gsub(/`[^`]+`/, '')
  body_without_code.scan(HASHTAG_PATTERN).flatten.map(&:downcase).uniq
end
```

#### Indexer Changes

```ruby
# In Indexer#index_note, after FTS update:

db.execute('DELETE FROM body_tags WHERE note_id = ?', [note.id])
hashtags = extract_body_hashtags(body)
hashtags.each do |tag|
  db.execute('INSERT INTO body_tags (note_id, tag) VALUES (?, ?)', [note.id, tag])
end
debug_print("Extracted #{hashtags.size} body hashtag(s)")
```

### 4.2 Updated Tag Command

```bash
zh tags                    # All tags (front matter + body)
zh tags --source frontmatter
zh tags --source body

# Output format:
# work (45) [frontmatter, body]
# project (32) [frontmatter]
# todo (15) [body]
```

#### Combined Query

```sql
SELECT tag, SUM(count) as total, GROUP_CONCAT(DISTINCT source) as sources
FROM (
  SELECT json_each.value as tag, COUNT(*) as count, 'frontmatter' as source
  FROM notes, json_each(json_extract(metadata, '$.tags'))
  GROUP BY json_each.value
  UNION ALL
  SELECT tag, COUNT(*) as count, 'body' as source
  FROM body_tags
  GROUP BY tag
)
GROUP BY tag
ORDER BY total DESC, tag ASC
```

### 4.3 Configuration

```yaml
tags:
  extract_body_hashtags: true
  normalize: true                # Lowercase all tags
  min_length: 2
  max_length: 50
  excluded_patterns:
    - "^[0-9]+$"                 # Pure numbers
    - "^[a-fA-F0-9]{6}$"        # Hex colors
```

---

## 5. Editor Integration: Neovim

### 5.1 Project Structure

```
zettelhub/
├── nvim/
│   └── lua/
│       └── zettelhub/
│           ├── init.lua       # Core module, config, utilities
│           ├── cmp.lua        # nvim-cmp completion source
│           ├── telescope.lua  # Telescope pickers
│           └── setup.lua      # Setup function, keymaps, commands
├── docs/
│   └── NEOVIM_INTEGRATION.md  # Detailed setup guide
```

### 5.2 Core Module (`nvim/lua/zettelhub/init.lua`)

```lua
local M = {}

M.config = {
  zh_command = 'zh',
  search_limit = 30,
  person_alias_prefix = '@',
  tag_prefix = '#',
  tag_completion_in_body = true,
}

-- Parse JSON from zh search
function M.parse_search_results(json_str)
  if not json_str or json_str == '' then return {} end
  local ok, results = pcall(vim.json.decode, json_str)
  if not ok then return {} end
  return results or {}
end

-- Sync search
function M.search(query, opts)
  opts = opts or {}
  local args = { 'search', '--format', 'json', '--limit', tostring(opts.limit or M.config.search_limit) }
  if opts.type then
    table.insert(args, '--type')
    table.insert(args, opts.type)
  end
  if query and query ~= '' then
    table.insert(args, query)
  end
  local cmd = M.config.zh_command .. ' ' .. table.concat(args, ' ') .. ' 2>/dev/null'
  local handle = io.popen(cmd)
  if not handle then return {} end
  local result = handle:read('*a')
  handle:close()
  return M.parse_search_results(result)
end

-- Async search using plenary.job
function M.search_async(query, opts, callback)
  opts = opts or {}
  local Job = require('plenary.job')
  local args = { 'search', '--format', 'json', '--limit', tostring(opts.limit or M.config.search_limit) }
  if opts.type then
    table.insert(args, '--type')
    table.insert(args, opts.type)
  end
  if query and query ~= '' then
    table.insert(args, query)
  end
  Job:new({
    command = M.config.zh_command,
    args = args,
    on_exit = function(job, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          callback({})
          return
        end
        local result = table.concat(job:result(), '\n')
        callback(M.parse_search_results(result))
      end)
    end,
  }):start()
end

-- Fetch all tags
function M.get_tags(query)
  local cmd = M.config.zh_command .. ' tags 2>/dev/null'
  local handle = io.popen(cmd)
  if not handle then return {} end
  local result = handle:read('*a')
  handle:close()
  local tags = {}
  for line in result:gmatch('[^\n]+') do
    local tag, count = line:match('^%s*([^%(]+)%s*%((%d+)%)')
    if tag then
      tag = vim.trim(tag)
      if not query or query == '' or tag:lower():find(query:lower(), 1, true) then
        table.insert(tags, { name = tag, count = tonumber(count) or 0 })
      end
    end
  end
  table.sort(tags, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)
  return tags
end

-- Get completion context
function M.get_completion_context(line, col)
  local before_cursor = line:sub(1, col)
  
  -- [[@... (person alias)
  local at_match = before_cursor:match('%[%[@([^%]]*)$')
  if at_match then
    return { type = 'person_alias', query = at_match, start_col = col - #at_match }
  end
  
  -- [[... (wikilink)
  local wikilink_match = before_cursor:match('%[%[([^%]]*)$')
  if wikilink_match then
    return { type = 'wikilink', query = wikilink_match, start_col = col - #wikilink_match }
  end
  
  -- #tag in body
  if M.config.tag_completion_in_body then
    local hashtag_match = before_cursor:match('#([%w%-_]*)$')
    if hashtag_match then
      return { type = 'hashtag', query = hashtag_match, start_col = col - #hashtag_match }
    end
  end
  
  return nil
end

-- Format wikilink
function M.format_wikilink(note, opts)
  opts = opts or {}
  if opts.use_at_alias and note.type == 'person' then
    local name = note.full_name or note.title or note.id
    return string.format('%s%s', M.config.person_alias_prefix, name)
  end
  return string.format('%s|%s', note.id, note.title or '')
end

M.setup = function(opts)
  require('zettelhub.setup').setup(opts)
end

return M
```

### 5.3 nvim-cmp Source (`nvim/lua/zettelhub/cmp.lua`)

```lua
local cmp = require('cmp')
local zettelhub = require('zettelhub')

local source = {}

source.new = function()
  return setmetatable({}, { __index = source })
end

source.get_trigger_characters = function()
  return { '[', '@', '#', ',', '-' }
end

source.is_available = function()
  return vim.bo.filetype == 'markdown'
end

source.complete = function(self, params, callback)
  local line = params.context.cursor_before_line
  local col = params.context.cursor.col
  local ctx = zettelhub.get_completion_context(line, col)
  
  if not ctx then
    callback({ items = {}, isIncomplete = false })
    return
  end
  
  -- Tag completion
  if ctx.type == 'hashtag' then
    zettelhub.get_tags_async(ctx.query, function(tags)
      local items = {}
      for _, tag in ipairs(tags) do
        table.insert(items, {
          label = '#' .. tag.name,
          insertText = tag.name,
          kind = cmp.lsp.CompletionItemKind.Keyword,
          detail = string.format('%d notes', tag.count),
        })
      end
      callback({ items = items, isIncomplete = false })
    end)
    return
  end
  
  -- Note completion
  local search_opts = { limit = 20 }
  if ctx.type == 'person_alias' then
    search_opts.type = 'person'
  end
  
  zettelhub.search_async(ctx.query, search_opts, function(notes)
    local items = {}
    for _, note in ipairs(notes) do
      local insert_text, label
      if ctx.type == 'person_alias' then
        local name = note.full_name or note.title or note.id
        insert_text = name
        label = '@' .. name
      else
        insert_text = zettelhub.format_wikilink(note)
        label = note.title or note.id
      end
      table.insert(items, {
        label = label,
        insertText = insert_text,
        kind = cmp.lsp.CompletionItemKind.Reference,
        detail = note.type or 'Note',
      })
    end
    callback({ items = items, isIncomplete = #notes >= 20 })
  end)
end

return source
```

### 5.4 Telescope Pickers (`nvim/lua/zettelhub/telescope.lua`)

```lua
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local zettelhub = require('zettelhub')

local M = {}

-- Insert wikilink picker
function M.insert_wikilink(opts)
  pickers.new(opts or {}, {
    prompt_title = 'Insert Wikilink',
    finder = finders.new_dynamic({
      fn = function(prompt)
        local notes = zettelhub.search(prompt, { limit = 50 })
        local entries = {}
        for _, note in ipairs(notes) do
          table.insert(entries, {
            value = note,
            display = string.format('[%s] %s', note.type or 'note', note.title or note.id),
            ordinal = (note.title or '') .. ' ' .. note.id,
          })
        end
        return entries
      end,
      entry_maker = function(entry) return entry end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          local note = selection.value
          local wikilink = string.format('[[%s|%s]]', note.id, note.title or '')
          vim.api.nvim_put({ wikilink }, '', true, true)
        end
      end)
      return true
    end,
  }):find()
end

-- Insert person (@mention) picker
function M.insert_person(opts)
  pickers.new(opts or {}, {
    prompt_title = 'Insert Person (@mention)',
    finder = finders.new_dynamic({
      fn = function(prompt)
        local notes = zettelhub.search(prompt, { type = 'person', limit = 50 })
        local entries = {}
        for _, note in ipairs(notes) do
          table.insert(entries, {
            value = note,
            display = note.full_name or note.title or note.id,
            ordinal = (note.full_name or '') .. ' ' .. (note.title or '') .. ' ' .. note.id,
          })
        end
        return entries
      end,
      entry_maker = function(entry) return entry end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          local note = selection.value
          local name = note.full_name or note.title or note.id
          vim.api.nvim_put({ '[[@' .. name .. ']]' }, '', true, true)
        end
      end)
      return true
    end,
  }):find()
end

-- Insert tag picker
function M.insert_tag(opts)
  pickers.new(opts or {}, {
    prompt_title = 'Insert Tag',
    finder = finders.new_dynamic({
      fn = function(prompt)
        local tags = zettelhub.get_tags(prompt)
        local entries = {}
        for _, tag in ipairs(tags) do
          table.insert(entries, {
            value = tag,
            display = string.format('#%-20s (%d)', tag.name, tag.count),
            ordinal = tag.name,
          })
        end
        return entries
      end,
      entry_maker = function(entry) return entry end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          vim.api.nvim_put({ '#' .. selection.value.name }, '', true, true)
        end
      end)
      return true
    end,
  }):find()
end

-- Browse notes
function M.browse(opts)
  pickers.new(opts or {}, {
    prompt_title = 'Browse ZettelHub',
    finder = finders.new_dynamic({
      fn = function(prompt)
        local notes = zettelhub.search(prompt, { limit = 100 })
        local entries = {}
        for _, note in ipairs(notes) do
          table.insert(entries, {
            value = note,
            display = string.format('[%s] %s', note.type or 'note', note.title or note.id),
            ordinal = (note.title or '') .. ' ' .. note.id,
          })
        end
        return entries
      end,
      entry_maker = function(entry) return entry end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection and selection.value.full_path then
          vim.cmd('edit ' .. vim.fn.fnameescape(selection.value.full_path))
        end
      end)
      return true
    end,
  }):find()
end

-- Insert organization
function M.insert_organization(opts)
  pickers.new(opts or {}, {
    prompt_title = 'Insert Organization',
    finder = finders.new_dynamic({
      fn = function(prompt)
        local notes = zettelhub.search(prompt, { limit = 50 })
        local entries = {}
        for _, note in ipairs(notes) do
          if note.type == 'organization' or note.type == 'account' then
            table.insert(entries, {
              value = note,
              display = string.format('[%s] %s', note.type, note.title or note.id),
              ordinal = (note.title or '') .. ' ' .. note.id,
            })
          end
        end
        return entries
      end,
      entry_maker = function(entry) return entry end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          local note = selection.value
          vim.api.nvim_put({ string.format('[[%s|%s]]', note.id, note.title or '') }, '', true, true)
        end
      end)
      return true
    end,
  }):find()
end

return M
```

### 5.5 Setup (`nvim/lua/zettelhub/setup.lua`)

```lua
local M = {}

function M.setup(opts)
  opts = opts or {}
  
  local zettelhub = require('zettelhub')
  zettelhub.config = vim.tbl_deep_extend('force', zettelhub.config, opts)
  
  -- Register nvim-cmp source
  local has_cmp, cmp = pcall(require, 'cmp')
  if has_cmp then
    local cmp_source = require('zettelhub.cmp')
    cmp.register_source('zettelhub', cmp_source.new())
    
    cmp.setup.filetype('markdown', {
      sources = cmp.config.sources({
        { name = 'zettelhub', priority = 1000 },
        { name = 'nvim_lsp', priority = 750 },
        { name = 'buffer', priority = 250 },
        { name = 'path', priority = 100 },
      }),
    })
  end
  
  -- Setup keymaps
  local telescope = require('zettelhub.telescope')
  
  -- Global keymaps
  vim.keymap.set('n', '<leader>zf', telescope.browse, { desc = 'ZettelHub: Browse' })
  vim.keymap.set('n', '<leader>zl', telescope.insert_wikilink, { desc = 'ZettelHub: Insert wikilink' })
  vim.keymap.set('n', '<leader>zp', telescope.insert_person, { desc = 'ZettelHub: Insert @person' })
  vim.keymap.set('n', '<leader>zo', telescope.insert_organization, { desc = 'ZettelHub: Insert org' })
  vim.keymap.set('n', '<leader>zt', telescope.insert_tag, { desc = 'ZettelHub: Insert tag' })
  
  -- Markdown-specific keymaps
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'markdown',
    callback = function(args)
      vim.keymap.set('i', '<C-l>', telescope.insert_wikilink, { buffer = args.buf, desc = 'Insert wikilink' })
      vim.keymap.set('i', '<C-p>', telescope.insert_person, { buffer = args.buf, desc = 'Insert @person' })
      vim.keymap.set('i', '<C-t>', telescope.insert_tag, { buffer = args.buf, desc = 'Insert tag' })
    end,
  })
  
  -- User commands
  vim.api.nvim_create_user_command('ZkBrowse', telescope.browse, { desc = 'Browse notes' })
  vim.api.nvim_create_user_command('ZkLink', telescope.insert_wikilink, { desc = 'Insert wikilink' })
  vim.api.nvim_create_user_command('ZkPerson', telescope.insert_person, { desc = 'Insert @person' })
  vim.api.nvim_create_user_command('ZkOrg', telescope.insert_organization, { desc = 'Insert org' })
  vim.api.nvim_create_user_command('ZkTag', telescope.insert_tag, { desc = 'Insert tag' })
end

return M
```

### 5.6 User Documentation (`docs/NEOVIM_INTEGRATION.md`)

See separate file for complete installation and configuration guide.

### 5.7 Keymaps Reference

#### Global (Normal Mode)

| Keymap | Action |
|--------|--------|
| `<leader>zf` | Browse notes |
| `<leader>zl` | Insert wikilink `[[id\|Title]]` |
| `<leader>zp` | Insert person `[[@Name]]` |
| `<leader>zo` | Insert organization |
| `<leader>zt` | Insert tag |

#### Markdown (Insert Mode)

| Keymap | Action |
|--------|--------|
| `<C-l>` | Open wikilink picker |
| `<C-p>` | Open person picker |
| `<C-t>` | Open tag picker |

#### Inline Completion

| Trigger | Completes |
|---------|-----------|
| `[[` | All notes → `id\|Title` |
| `[[@` | People → `@Name` |
| `#` | Tags → `tagname` |

### 5.8 Coexistence with Marksman

| Feature | Provider |
|---------|----------|
| Wikilinks `[[` | ZettelHub |
| @mentions `[[@` | ZettelHub |
| Tags `#` | ZettelHub |
| Headings, diagnostics | Marksman |
| Document outline | Marksman |

No conflicts - ZettelHub's cmp source has higher priority and only activates on specific triggers.

---

## 6. Implementation

### 6.1 Files to Create/Modify

| File | Action | Phase |
|------|--------|-------|
| `lib/template_vars.rb` | Create | 1 |
| `lib/prompt_executor.rb` | Create | 2 |
| `lib/prompt_collector.rb` | Create | 2 |
| `lib/option_source.rb` | Create | 2 |
| `lib/condition_evaluator.rb` | Create | 2 |
| `lib/value_transformer.rb` | Create | 2 |
| `lib/value_validator.rb` | Create | 2 |
| `lib/models/person.rb` | Create | 3 |
| `lib/cmd/person.rb` | Create | 3 |
| `lib/templates/person.erb` | Create | 3 |
| `lib/models/organization.rb` | Create | 4 |
| `lib/models/account.rb` | Create | 4 |
| `lib/cmd/org.rb` | Create | 4 |
| `lib/templates/organization.erb` | Create | 4 |
| `lib/utils.rb` | Modify (hierarchy methods) | 4 |
| `lib/vcf_parser.rb` | Create | 5 |
| `lib/indexer.rb` | Modify (hashtag extraction) | 6 |
| `lib/cmd/tag.rb` | Modify (sources) | 6 |
| `nvim/lua/zettelhub/init.lua` | Create | 7 |
| `nvim/lua/zettelhub/cmp.lua` | Create | 7 |
| `nvim/lua/zettelhub/telescope.lua` | Create | 7 |
| `nvim/lua/zettelhub/setup.lua` | Create | 7 |
| `docs/NEOVIM_INTEGRATION.md` | Create | 7 |
| `bin/zh` | Modify (add routes) | 3, 4 |
| Tests for all above | Create | All |

### 6.2 Phased Rollout

| Phase | Features | Dependencies |
|-------|----------|--------------|
| **1** | Template Variables | None |
| **2** | Dynamic Prompts | Phase 1 |
| **3** | Person model, template, commands | Phase 2 |
| **4** | Organization, Account, hierarchy | Phase 3 |
| **5** | VCF import/export | Phase 3 |
| **6** | Hashtag extraction, tag enhancements | None |
| **7** | Neovim integration | Phase 3, 6 |

### 6.3 Testing Strategy

- Unit tests for each new module
- Integration tests for command workflows
- Template rendering tests with custom variables
- Prompt collection tests (mock stdin/gum)
- Indexer tests for hashtag extraction
- No interactive prompts in tests

---

## 7. Configuration Reference

### 7.1 Template Prompts Schema

```yaml
config:
  prompts:
    - key: string              # Variable name (required)
      type: input|write|choose|filter|confirm  # Prompt type (required)
      placeholder: string      # Prompt text
      required: boolean        # Must have value
      default: any             # Default value (supports ERB)
      hidden: boolean          # Compute only, don't prompt
      when: string             # Condition expression
      options: [...]           # Static options (choose/filter)
      source:                  # Dynamic options
        type: tags|notes|files|command
        filter: regex
        sort: alpha|count|recent
        limit: integer
      transform: [...]         # Value transformations
      validate:                # Validation rules
        type: url|email|date
        pattern: regex
        message: string
```

### 7.2 Contact Management Config

```yaml
person:
  stale_threshold_days: 90
  birthday_lookahead_days: 30
  import:
    default_format: "vcf"
    duplicate_strategy: "prompt"
  export:
    vcf_version: "4.0"
    default_output: "people.vcf"

organization:
  default_path_pattern: "organizations/{slugify(name)}-{id}.md"
```

### 7.3 Tag Config

```yaml
tags:
  extract_body_hashtags: true
  normalize: true
  min_length: 2
  max_length: 50
  excluded_patterns:
    - "^[0-9]+$"
    - "^[a-fA-F0-9]{6}$"
```

---

## Related Documentation

- [ARCHITECTURE.md](../ARCHITECTURE.md) - System architecture
- [AGENTS.md](../AGENTS.md) - Development guidelines
- [NEOVIM_INTEGRATION.md](NEOVIM_INTEGRATION.md) - Detailed Neovim setup
