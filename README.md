# Writebook — Marten / Crystal port

A port of [Basecamp's Writebook](https://github.com/basecamp/writebook) (Once: Campfire-line content publisher) from **Rails** to **[Marten](https://martenframework.com) + Crystal**.

The user-facing surface aims at byte-level parity with the original: same CSS class vocabulary, same icons, same Hotwire-driven UX (Turbo Frames + Streams over HTTP and Action Cable, Stimulus on the client, drag-arrange, autosave, real-time "X is editing" indicators, FTS5 search, lock/web publication toggle, QR-code share, session-transfer links, custom-styles CSS editor, markdown export).

Under the hood it's idiomatic Crystal — Marten apps for the book/account domains, polymorphic leafable models via `field :leafable, :polymorphic, to: [...]` + a `delegated_type` macro, `marten-turbo` for Hotwire integration, `marten-cable` for WebSockets, `markd` + `tartrazine` for Markdown + syntax highlighting, `crystal-vips` for image variants, `goban` for QR codes.

## Lineage

This repo is a fork of `basecamp/writebook`. The original Rails source is preserved on the [`rails-archive`](../../tree/rails-archive) branch as a frozen reference for parity comparisons. The `main` branch contains only the Crystal port.

The `MIT-LICENSE` is from 37signals and applies to the original Writebook source. The Crystal port is contributed under the same license.

## Running in development

You'll need [Crystal](https://crystal-lang.org) 1.20+ installed via [asdf](https://github.com/asdf-vm/asdf) or directly.

```sh
shards install
script/manage migrate
script/manage seed_manual   # optional: seeds the Writebook Manual demo book
script/serve                # builds + runs at http://127.0.0.1:8000
```

Visit `http://127.0.0.1:8000/first_run` on a fresh DB to create the singleton account and the first administrator user.

`script/serve` and `script/manage` are wrappers that export `CRYSTAL_LIBRARY_PATH` because asdf 0.18 (the Go rewrite) doesn't propagate it the way the bash asdf-crystal plugin did. Use these instead of invoking `crystal` directly.

## Architecture

Two Marten apps:

- **`books/`** — Book, Leaf, Edit, Markdown, Leafables::{Page, Section, Picture}, Attachment. Handlers for the book index/show/edit, leaf show/edit (per type), accesses, publications, bookmarks, search, markdown export. Owns the FTS5 index.
- **`accounts/`** — Account (singleton workspace), User (via `marten-auth`), Access (per-book editor/reader), Session. First-run flow, sign-in/out, profiles, custom-styles editor, join codes, QR-code share, session-transfer.

See [`STATUS.md`](STATUS.md) for the porting log, build state, and gotchas worth remembering. See [`RAILS_TO_MARTEN.md`](RAILS_TO_MARTEN.md) for the porting playbook — Rails idiom ↔ Marten/Crystal recipe per pattern (polymorphic associations, concerns, has_secure_password, ActiveSupport::CurrentAttributes, etc).

## Comparing against the Rails original

The [`rails-archive`](../../tree/rails-archive) branch has the Rails source frozen at the fork point. To compare a feature:

```sh
git worktree add ../writebook-rails rails-archive
# now ../writebook-rails/ is the Rails source, ./ is the Crystal port
```

This pattern was the most valuable debugging tool during the port — visual + structural parity was diffed file-by-file.

## License

MIT, per the upstream Writebook. See `MIT-LICENSE`.
