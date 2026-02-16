# Task management – enhancement plan

How to add task management to ZettelHub, including standalone task notes, inline `- [ ]` checklists, and creating tasks from within notes or journals.

---

## 1. What already exists

- **Document types** (note, journal, meeting, bookmark) via templates and `metadata['type']`.
- **Index:** `notes` table with `metadata` (JSON); search uses `json_extract(n.metadata, '$.type')` and `$.date`.
- **Search:** `zh search --type X --date Y`; filters are metadata-based.
- **Add flow:** `zh add` + template type (e.g. `zh add task` once a task template exists).

Tasks can be "notes with `type: task`" and extra fields in the same metadata. No new table is required for standalone tasks.

---

## 2. Task model and template

**Option A – No new model (simplest)**  
Treat tasks as notes: `type: task` in front matter, plus e.g. `due_date`, `status`, `priority` in YAML. The existing indexer and search already store and index metadata; you only need to query it.

**Option B – Task model**  
Add `lib/models/task.rb` inheriting from `Note` (or `Document`) with helpers like `due_date`, `status`, `priority` parsed from metadata. Same storage format, clearer API and validation.

**Template**  
Add `lib/templates/task.erb` (and optional user overrides in `.zh/templates/` or `~/.config/zh/templates/`) with front matter like:

```yaml
type: task
due_date: "<%= due_date %>"
status: "<%= status %>"
priority: "<%= priority %>"
title: ...
```

Use the same `config.path` pattern as other types (e.g. `tasks/<%= id %>-<%= slugify(title) %>.md`). Then `zh add task` works with the existing add command.

---

## 3. Commands

- **`zh task list`** (or `zh tasks`)  
  - Run the existing search with `--type task` and optional filters.
  - Add filters for due date and status by extending the search command or the task command:
    - `zh task list --due today|overdue|2026-02-15|2026-02`
    - `zh task list --status open|done|cancelled`
  - Implementation: either call the same search logic used by `zh search` (same DB, `json_extract` on `metadata`) or add a small wrapper in `lib/cmd/task.rb` that builds type + due/status filters and reuses the search execution path. Output: list/table/JSON like search; optional fzf for interactive choice then open in editor.

- **`zh task add`**  
  - Wrapper around `zh add task` with task-specific defaults (e.g. `status: open`, `due_date: today`) and flags like `--due`, `--priority`. Can delegate to the existing add command with the task template and passed-through options.

- **`zh task done NOTE_ID`** (optional)  
  - Update the note's front matter: set `status: done` (and optionally `completed_at`). Implement by reading the file, parsing YAML, updating metadata, writing back; then run the indexer for that note so the index stays in sync.

---

## 4. Search/indexer extensions

- **Search**  
  - Already supports `--type task` once notes have `type: task`.
  - Add **due date** filter: e.g. `--due 2026-02-15` or `--due today` (range for that day). In `execute_search` (or the shared query builder), add a `due_date` condition using `json_extract(n.metadata, '$.due_date')` and the same kind of date parsing you use for `date` (single day, month, or range). Reuse from `zh task list`.
  - Optionally **status** filter: `json_extract(n.metadata, '$.status') = ?`.

- **Indexer**  
  - No schema change. It already stores full metadata as JSON. Ensure task notes are reindexed after creation/update (existing add flow and any "task done" file update should call the indexer).

---

## 5. Journal and "today" integration

- In the **journal** flow (see [JOURNAL_GOOGLE_CALENDAR_AGENDA_PLAN.md](JOURNAL_GOOGLE_CALENDAR_AGENDA_PLAN.md)), you already plan to inject a "daily overview" (e.g. agenda from Google Calendar).
- Add a **"Tasks due today"** block the same way:
  - When rendering the journal for date D, query the index for `type=task`, `due_date` in range for D, and optionally `status != done`.
  - Format as markdown (e.g. list of task titles + links or IDs) and pass as another template variable (e.g. `tasks_due_today`) into the journal template.
- Same extension point as the calendar agenda: one more optional "content block" filled before rendering the journal template.

---

## 6. Config

Under `config.yaml` (and getters in `lib/config.rb`), add optional task defaults, e.g.:

```yaml
task:
  default_status: open
  default_priority: medium
  status_values: [open, in_progress, done, cancelled]
  list_default_due: today   # default filter for zh task list
```

Use these when creating tasks (`zh task add` / task template) and when no filter is given for `zh task list`.

---

## 7. Two sources of tasks: standalone vs inline

| Source | What it is | Today |
|--------|------------|--------|
| **Standalone task** | Note with `type: task` and front matter (due_date, status, etc.) | Created via `zh task add` / `zh add task`; indexed; in `zh task list`. |
| **Inline task** | A `- [ ]` (or `- [x]`) line in the body of any note or journal | Just markdown; not a separate note; not in the index as a "task". |

We need to decide how inline items participate in "task management" and how the two interact.

---

## 8. UX choices for inline checklists

**A. Index inline checklists as tasks**

- **Idea:** During index, parse note/journal bodies for `- [ ]` and `- [x]`, and store each as a "task-like" row (or as a structured part of metadata) so they can be queried.
- **Pros:** One "task list" (e.g. `zh task list`) can show both standalone task notes and inline items, with "source" = path + line (or note id).
- **Cons:** Schema and indexer get more complex (task rows or JSON blobs with line numbers, path, snippet). Updating "status" means rewriting the note file (e.g. toggling `[ ]` ↔ `[x]`). Due dates and priority for inline items need a convention (see below).

**B. Don't index inline; treat as display-only**

- **Idea:** `- [ ]` stays pure markdown. "Task management" = only standalone task notes. Journals/notes can still show "inline todos" in their own view (e.g. "today's journal" shows its checklist when you open it).
- **Pros:** Simple; no indexer changes; no ambiguity about what's a "task".
- **Cons:** Inline items never appear in `zh task list` or in "tasks due today" unless we add a separate "show checklists from this note" view.

**C. Hybrid (recommended)**

- **Standalone task notes** remain the primary "task management" object (due date, status, priority, `zh task list`, journal "tasks due today").
- **Inline `- [ ]`** are first-class in the **UI** and in **one** unified list, but not necessarily in the same DB table as notes:
  - **Option C1 – Index inline as "synthetic" tasks:** Indexer (or a separate pass) finds `- [ ]` / `- [x]` in body, writes rows to a `checklist_items` (or `inline_tasks`) table with: note_id, path, line/snippet, "status" (open/done from `[ ]`/`[x]`), optional metadata (see below). `zh task list` then merges: "task" notes + these rows, with a "source" column (e.g. "journal/2026-02-11.md" vs "task note abc123").
  - **Option C2 – No indexing; on-the-fly aggregation:** `zh task list` only shows standalone task notes. A separate command or flag, e.g. `zh task list --include-checklists`, runs ripgrep (or a scanner) over markdown files for `- [ ]`, and merges those into the list in memory (with path + line). No schema change; list is "tasks + inline items" only when user asks.

C2 is simpler to ship; C1 gives faster and filterable "all my tasks including inline" without re-scanning files each time.

---

## 9. Inline syntax for due date / priority (if we index or aggregate)

If we want inline items to support due dates and appear in "tasks due today" or "by priority", we need a convention that's still readable as markdown:

- **Option 1 – Attribute line:**  
  `- [ ] My task *(due: 2026-02-15)*` or `- [ ] My task {due: 2026-02-15}`  
  Parser extracts the date; store it when indexing or when building the aggregated list.

- **Option 2 – Separate line (metadata):**  
  ```markdown
  - [ ] My task
    due: 2026-02-15
  ```  
  Same idea; a bit more verbose.

- **Option 3 – No dates for inline:**  
  Inline items are "undated" and only appear in "all tasks" or "tasks from this note"; "due today" and "by date" only apply to standalone task notes. Simplest and keeps markdown minimal.

Recommendation: start with **Option 3**; introduce optional metadata (Option 1 or 2) only if you add indexing/aggregation of inline items.

---

## 10. Creating a task while editing a note or journal

**Goal:** From inside a note or journal, user can create a *standalone* task with minimal friction and without losing context (current file, or link from task back to note).

**Flows:**

- **From editor (current note = context):**  
  - **A.** User runs a command from the shell, e.g. `zh task add --title "Follow up with X" --from "$(current file)"`. "From" could be an env var or a small helper that passes the path of the "current" note (e.g. your editor sets `ZH_CURRENT_NOTE_PATH` when opening a file with zh).  
  - **B.** Editor integration: e.g. in Neovim/VSCode, a mapping or command that (1) takes the current line or selection as title, (2) calls `zh task add --title "..." --link-to <current-note-id>`, (3) optionally inserts a link to the new task in the current note (`[[task-id]]` or `[title](path)`).  
  - **C.** No "from" in the first version: user runs `zh task add` in a separate terminal; they can manually add a `[[task-id]]` in the note later. Easiest to implement.

- **Linking:**  
  When creating a task "from" a note, the tool can:
  - Add to the task note's body or front matter a "source" or "context" link to that note (e.g. `context: [[journal-2026-02-11]]` or a wikilink in the body).  
  - Optionally insert at the cursor (or at the end of the current note) a link to the new task, so the note now references the task.  
  That way both "note → task" and "task → note" are navigable and backlinks stay consistent.

**Optimal UX (short term):** Support "create task from current note" via (A) or (B), with `--link-to` / `--from` and automatic backlink (or link in task body). In-editor creation (B) is best UX but depends on editor integration; (A) is enough for "I'm in this note, I want a task that's tied to it."

---

## 11. Inline `- [ ]` and "promotion"

**Promote to task:**  
From a note that contains `- [ ] Some thing`, the user might want to turn "Some thing" into a real task note (with due date, status, etc.). Flow:

- **Command:** e.g. `zh task promote <note_id> --line 42` or `zh task promote --path path/to/note.md --line 42`.  
  - Tool reads the file, finds the line (e.g. line 42), parses `- [ ] Title` (and optional metadata if you support it).  
  - Creates a new task note with that title (and optional due/priority from inline metadata).  
  - Replaces the line with `- [ ] [[new-task-id]] Title` or `- [x] ...` if you want to mark the inline item done and have the standalone task as "open".  
  - Optionally adds a "Created from …" link in the task note.  
  So: one explicit "promote" action, then the checklist line becomes a link to the real task.

**Demote (task → inline):**  
Less common, but possible: "convert this task note into a `- [ ]` line in note X" (e.g. for a journal). Could be a later feature.

---

## 12. Journal "daily overview" and tasks

- **Standalone tasks:** "Tasks due today" in the journal = query by `type=task` and `due_date=today`; inject that list into the journal template (as in section 5).
- **Inline:** If we aggregate or index inline items:
  - "Checklist items in this journal" = all `- [ ]` / `- [x]` in *this* journal file. Could be rendered in the same "Daily overview" block (e.g. "Tasks due today" from index + "Checklist" from current file body).  
  - If we don't index inline, we could still have the journal template (or a post-process step) include a "Checklist" section that's populated by scanning the *current* file for `- [ ]` after it's opened—so the user sees "today's tasks (from index)" and "today's checklist (from this journal)" in one place.

So the "optimal" experience is: one daily view that can show both "task notes due today" and "inline checklist from this journal" (and optionally from other notes), even if only the former is in the index at first.

---

## 13. Recurrence and reminders (later)

- **Recurrence:** Store a rule in metadata (e.g. `recurrence: "weekly"` or an iCal-style string). When listing "tasks due today", expand recurrence for the given date in code; no need to store every instance in the index. More complex recurrence can be phased in.
- **Reminders:** Either a separate "reminder at time T" store (e.g. sidecar or metadata) plus a daemon/cron that notifies, or integration with system/calendar (e.g. Google Calendar) so "remind me" creates an event. Out of scope for the minimal task design.

---

## 14. Recommended priorities

| Priority | What | Why |
|----------|------|-----|
| 1 | Standalone task notes + `zh task list` (and optional "tasks due today" in journal) | Clear, implementable, no ambiguity. |
| 2 | "Create task from current note" with `--from` / `--link-to` and auto-link task ↔ note | Covers "I'm in a note/journal and want a real task linked here." |
| 3 | `zh task list --include-checklists` (on-the-fly grep for `- [ ]` and merge into list) | Single list of "tasks + inline" without schema change. |
| 4 | Optional: index inline items (C1) and/or inline metadata (due/priority) | Only if you want "due today" and sorting for inline items. |
| 5 | "Promote" inline line to task note + replace with link | Nice when a checklist item becomes a real task. |

This keeps the optimal user experience in mind: **low friction** (typing `- [ ]` in a note/journal is already good), **one place to see everything** (unified list with `--include-checklists` or indexed inline), and **clear path from "inline idea" to "managed task"** (promote, and create-from-note with linking).

---

## 15. Summary table

| Area | Enhancement |
|------|-------------|
| **Data** | Tasks = notes with `type: task`; add `due_date`, `status`, `priority` (and optionally `completed_at`) in front matter. No DB schema change. |
| **Template** | Add `task.erb`; register type in config/defaults so `zh add task` works. |
| **Commands** | `zh task list` (reuse search + due/status filters), `zh task add` (wrap add with task defaults), optionally `zh task done NOTE_ID`, `zh task promote` (inline → task), `--from`/`--link-to` for create-from-note. |
| **Search** | Add due-date (and optionally status) filters using `json_extract` on metadata. |
| **Journal** | When rendering a day's journal, query tasks due that day and inject a "Tasks due today" section; optionally show inline checklist from that journal file. |
| **Inline** | Support `--include-checklists` in task list (on-the-fly); optionally index or parse inline metadata later. |
| **Config** | `task:` section for default status, priority, and list behavior. |
