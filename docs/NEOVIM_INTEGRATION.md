# ZettelHub Neovim Integration

Complete guide for integrating ZettelHub with Neovim using nvim-cmp and Telescope.

## Overview

This integration provides:
- **Inline completion** for wikilinks, @person mentions, and #tags
- **Telescope pickers** for browsing and inserting notes
- **Coexistence** with Marksman LSP

## Prerequisites

- Neovim 0.9+
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- ZettelHub CLI (`zh`) in PATH

## Installation

### Option 1: Via make install (recommended)

When you run `make install`, the Neovim integration is automatically installed to
`~/.config/zh/nvim/`. Add this to your `init.lua`:

```lua
-- Add ZettelHub's nvim directory to runtimepath
vim.opt.runtimepath:append(vim.fn.expand('~/.config/zh/nvim'))

-- Load and setup
require('zettelhub').setup({
  zh_command = 'zh',
  search_limit = 30,
})
```

### Option 2: Manual runtimepath

If you haven't run `make install`, add the source directory:

```lua
-- Add ZettelHub's nvim directory to runtimepath
vim.opt.runtimepath:append('/path/to/zettelhub/nvim')

-- Load and setup
require('zettelhub').setup({
  zh_command = 'zh',
  search_limit = 30,
})
```

### Option 3: Symlink

Create a symlink in your Neovim config:

```bash
# From your Neovim config directory
ln -s /path/to/zettelhub/nvim/lua/zettelhub ~/.config/nvim/lua/zettelhub
```

Then in `init.lua`:

```lua
require('zettelhub').setup()
```

### Option 4: lazy.nvim

```lua
{
  dir = vim.fn.expand('~/.config/zh/nvim'),  -- or '/path/to/zettelhub/nvim'
  name = 'zettelhub',
  dependencies = {
    'hrsh7th/nvim-cmp',
    'nvim-telescope/telescope.nvim',
    'nvim-lua/plenary.nvim',
  },
  ft = 'markdown',
  config = function()
    require('zettelhub').setup({
      zh_command = 'zh',
    })
  end,
}
```

## Configuration

### Full Options

```lua
require('zettelhub').setup({
  -- Path to zh command (default: 'zh')
  zh_command = 'zh',
  
  -- Max results from search (default: 30)
  search_limit = 30,
  
  -- Prefix for person aliases (default: '@')
  person_alias_prefix = '@',
  
  -- Prefix for tags (default: '#')
  tag_prefix = '#',
  
  -- Enable tag completion in note body (default: true)
  tag_completion_in_body = true,
})
```

### Integrating with Existing nvim-cmp Setup

If you already have nvim-cmp configured, add the ZettelHub source:

```lua
local cmp = require('cmp')

cmp.setup({
  -- Your existing config...
  sources = cmp.config.sources({
    { name = 'nvim_lsp' },
    { name = 'luasnip' },
    -- Add other sources...
  }),
})

-- Add ZettelHub for markdown files with higher priority
cmp.setup.filetype('markdown', {
  sources = cmp.config.sources({
    { name = 'zettelhub', priority = 1000 },  -- Highest priority
    { name = 'nvim_lsp', priority = 750 },
    { name = 'buffer', priority = 250 },
    { name = 'path', priority = 100 },
  }),
})
```

## Keymaps

### Default Keymaps

The setup function registers these keymaps automatically:

#### Normal Mode (Global)

| Keymap | Action |
|--------|--------|
| `<leader>zf` | Browse all notes |
| `<leader>zl` | Insert wikilink picker |
| `<leader>zp` | Insert @person picker |
| `<leader>zo` | Insert organization picker |
| `<leader>zt` | Insert #tag picker |

#### Insert Mode (Markdown only)

| Keymap | Action |
|--------|--------|
| `<C-l>` | Open wikilink picker |
| `<C-p>` | Open @person picker |
| `<C-t>` | Open #tag picker |

### Custom Keymaps

Override the defaults by setting keymaps after setup:

```lua
require('zettelhub').setup()

local telescope = require('zettelhub.telescope')

-- Custom normal mode keymaps
vim.keymap.set('n', '<leader>nn', telescope.browse, { desc = 'Browse notes' })
vim.keymap.set('n', '<leader>nl', telescope.insert_wikilink, { desc = 'Insert link' })
vim.keymap.set('n', '<leader>np', telescope.insert_person, { desc = 'Insert person' })
vim.keymap.set('n', '<leader>no', telescope.insert_organization, { desc = 'Insert org' })
vim.keymap.set('n', '<leader>nt', telescope.insert_tag, { desc = 'Insert tag' })

-- Custom insert mode keymaps for markdown
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function(args)
    vim.keymap.set('i', '<C-n>', telescope.insert_wikilink, { buffer = args.buf })
    vim.keymap.set('i', '<C-@>', telescope.insert_person, { buffer = args.buf })
  end,
})
```

## Inline Completion

The nvim-cmp source provides automatic completion as you type:

### Wikilinks

Type `[[` to trigger completion for all notes:

```
[[pro⎸
  ┌─────────────────────────────────────┐
  │ Project Alpha                       │
  │ Project Beta                        │
  │ Project Management Notes            │
  └─────────────────────────────────────┘
```

Select a result to insert `[[abc123|Project Alpha]]`.

### Person Mentions

Type `[[@` to trigger completion for people only:

```
[[@jane⎸
  ┌─────────────────────────────────────┐
  │ @Jane Smith                         │
  │ @Jane Doe                           │
  └─────────────────────────────────────┘
```

Select a result to insert `[[@Jane Smith]]`.

### Tags

Type `#` in the note body to trigger tag completion:

```
#pro⎸
  ┌─────────────────────────────────────┐
  │ #project (45 notes)                 │
  │ #productivity (23 notes)            │
  │ #programming (18 notes)             │
  └─────────────────────────────────────┘
```

Select a result to insert `#project`.

## Telescope Pickers

Use the Telescope pickers for a full-screen fuzzy search experience:

```
┌───────────────────────────────────────────────────────────────┐
│ Insert Wikilink                                               │
├───────────────────────────────────────────────────────────────┤
│ > project                                                     │
├───────────────────────────────────────────────────────────────┤
│ > [note] Project Alpha                                        │
│   [meeting] Project Alpha Kickoff                             │
│   [note] Project Beta                                         │
│   [person] Jane Smith (Project Lead)                          │
└───────────────────────────────────────────────────────────────┘
```

## User Commands

The following Vim commands are available:

| Command | Description |
|---------|-------------|
| `:ZkBrowse` | Browse and open notes |
| `:ZkLink` | Insert wikilink |
| `:ZkPerson` | Insert @person mention |
| `:ZkOrg` | Insert organization link |
| `:ZkTag` | Insert tag |

## Coexistence with Marksman LSP

ZettelHub's completion works alongside Marksman without conflicts:

| Feature | Provider |
|---------|----------|
| Wikilinks `[[` | ZettelHub (higher priority) |
| @mentions `[[@` | ZettelHub |
| Body tags `#` | ZettelHub |
| Markdown diagnostics | Marksman |
| Document outline | Marksman |
| Heading references | Marksman |

### Why No Conflicts?

1. ZettelHub's cmp source has **priority 1000** (highest)
2. It only activates on specific triggers: `[[`, `[[@`, `#`
3. For all other completions, Marksman and other sources take over

### Recommended LSP Config

```lua
require('lspconfig').marksman.setup({
  -- Your Marksman config
})

-- ZettelHub handles wikilinks, Marksman handles everything else
require('zettelhub').setup()
```

## Complete init.lua Example

```lua
-- Plugin manager (lazy.nvim example)
require('lazy').setup({
  -- LSP
  {
    'neovim/nvim-lspconfig',
    config = function()
      require('lspconfig').marksman.setup({})
    end,
  },
  
  -- Completion
  {
    'hrsh7th/nvim-cmp',
    dependencies = {
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'L3MON4D3/LuaSnip',
      'saadparwaiz1/cmp_luasnip',
    },
    config = function()
      local cmp = require('cmp')
      cmp.setup({
        snippet = {
          expand = function(args)
            require('luasnip').lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
          { name = 'buffer' },
          { name = 'path' },
        }),
      })
    end,
  },
  
  -- Telescope
  {
    'nvim-telescope/telescope.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
  },
  
  -- ZettelHub (local plugin)
  {
    dir = '/path/to/zettelhub/nvim',
    name = 'zettelhub',
    ft = 'markdown',
    dependencies = {
      'hrsh7th/nvim-cmp',
      'nvim-telescope/telescope.nvim',
    },
    config = function()
      require('zettelhub').setup({
        zh_command = 'zh',
        search_limit = 30,
      })
    end,
  },
})
```

## Troubleshooting

### Completion Not Triggering

1. Verify `zh` is in PATH: `which zh`
2. Check filetype: `:set filetype?` should show `markdown`
3. Verify source is loaded: `:lua print(vim.inspect(require('cmp').get_registered_sources()))`

### No Results

1. Test search manually: `zh search --format json test`
2. Check index: `zh index`
3. Verify notebook path: `zh config --get notebook.path`

### Telescope Picker Empty

1. Ensure plenary.nvim is installed
2. Test: `:lua require('zettelhub').search('test')`

### Conflicts with Other Plugins

If another plugin handles `[[`, adjust priorities:

```lua
cmp.setup.filetype('markdown', {
  sources = cmp.config.sources({
    { name = 'zettelhub', priority = 1000 },  -- Ensure highest
    { name = 'other_source', priority = 500 },
  }),
})
```

## API Reference

### Core Functions

```lua
local zh = require('zettelhub')

-- Synchronous search
local notes = zh.search('query', { type = 'person', limit = 20 })

-- Async search
zh.search_async('query', {}, function(notes)
  -- Handle results
end)

-- Get all tags
local tags = zh.get_tags('filter')

-- Format wikilink
local link = zh.format_wikilink(note, { use_at_alias = true })

-- Get completion context
local ctx = zh.get_completion_context(line, col)
```

### Telescope Pickers

```lua
local telescope = require('zettelhub.telescope')

telescope.browse()              -- Browse all notes
telescope.insert_wikilink()     -- Insert [[id|Title]]
telescope.insert_person()       -- Insert [[@Name]]
telescope.insert_organization() -- Insert org link
telescope.insert_tag()          -- Insert #tag
```
