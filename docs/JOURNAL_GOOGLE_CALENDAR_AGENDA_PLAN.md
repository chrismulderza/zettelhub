# Journal + Google Calendar daily agenda – extension plan

How to extend the journal module so the daily journal can include a Google Calendar agenda.

---

## 1. Where it fits in the current flow

The journal command in `lib/cmd/journal.rb` does roughly:

1. Resolve date (today / yesterday / tomorrow / explicit date).
2. Get journal template and compute the file path for that date.
3. If the file doesn't exist: **render the template** with time vars → create the note → open in editor.
4. If it exists: open in editor.
5. Index the note after edit.

The place to add "daily agenda" is **before or during step 3**: compute the agenda for that date and pass it into the template as one or more variables (e.g. `agenda` or `daily_agenda`). The template can then render a "Daily Overview" or "Agenda" section.

---

## 2. Extension approaches

**Option A – Template variable (recommended)**  
Fetch calendar events for the journal date, format them as markdown, and pass a string into the template (e.g. `vars['agenda']` or `vars['daily_agenda']`). The journal template (`lib/templates/journal.erb`) already has a "Daily Overview" section; you can render the agenda there, e.g.:

```erb
## Daily Overview
<%= agenda %>
```

(or a new `## Agenda` section). The journal command would:

- Check config for "agenda enabled" (e.g. `journal.agenda.source: google_calendar`).
- Call a small calendar adapter that returns a string (markdown list of events).
- Merge that string into the same `vars` hash used in `render_journal_template` (and, if you use a template `config.path`, into the same context used for path interpolation).

**Option B – Post-render insertion**  
Render the template as today, then do a string insert (e.g. after "## Daily Overview") with the agenda markdown. Simpler in concept but more brittle (depends on exact heading text) and harder to customize per-template. Option A is cleaner.

**Option C – Separate "agenda" command**  
Add something like `zh journal-agenda [DATE]` that only fetches and prints (or writes) the agenda. The journal module could then call the same agenda fetcher internally for Option A, so the daily journal file still gets the agenda when you run `zh today` / `zh journal <date>`.

---

## 3. What you'd add in code

- **Config** (e.g. under `journal:` in `examples/config/config.yaml` and getters in `lib/config.rb`):
  - `journal.agenda.enabled` (boolean).
  - `journal.agenda.source: google_calendar`.
  - `journal.agenda.calendar_id` (e.g. `primary` or a specific ID).
  - `journal.agenda.credentials_path` (path to service account JSON or OAuth client secrets).

- **Calendar client** (new file, e.g. `lib/calendar_client.rb` or `lib/google_calendar.rb`):
  - Use the Google Calendar API (e.g. `google-apis-calendar_v3` gem) with a service account or OAuth.
  - Method like `events_for_date(date)` returning an array of hashes (start, end, summary, optional description).
  - A small formatter that turns that into markdown (e.g. "- 09:00 – 10:00 Meeting title") and returns a string.

- **Journal command** (in `lib/cmd/journal.rb`):
  - In `render_journal_template`, before calling the template:
    - If `journal.agenda.enabled` and source is `google_calendar`, call the calendar client for `resolved_date`, format to markdown, set `vars['agenda'] = that_string` (or `vars['daily_agenda']`).
    - If calendar is disabled or fails, set `vars['agenda'] = ''` (or a one-line "No agenda configured").
  - Use the same `vars` when rendering the ERB template so `<%= agenda %>` (or your chosen name) appears in the right section.

- **Template**  
  In `lib/templates/journal.erb` (and any user overrides), add something like:

  ```erb
  ## Daily Overview
  <%= agenda %>
  ```

  so the generated journal gets the daily agenda when the feature is enabled.

- **Docs**  
  In README/AGENTS.md, document the new `journal.agenda` options and that the journal template can use the `agenda` variable.

---

## 4. Google Calendar API details

- **Auth:** Service account (no browser) or OAuth (user's own calendar). Service account needs the calendar shared with the service account email.
- **Gem:** e.g. `google-apis-calendar_v3` plus `googleauth` for credentials.
- **API:** "Events: list" for the chosen calendar ID, time bounds = start/end of the requested date (in the user's or config time zone), single events, order by start time.
- **Credentials:** Store the JSON key path in config (e.g. `journal.agenda.credentials_path`); do not commit the file. Optional: support `GOOGLE_APPLICATION_CREDENTIALS` env var as override.

---

## 5. Summary

- **Extend the journal module** by: (1) adding optional config under `journal.agenda`, (2) implementing a small Google Calendar fetcher that returns markdown for a given date, (3) in the journal command, before rendering the journal template, calling that fetcher and setting `vars['agenda']`, and (4) using `<%= agenda %>` in the journal template (e.g. under "Daily Overview"). That gives you a daily agenda in the same journal file without changing the rest of the journal flow (path, editor, indexing).
