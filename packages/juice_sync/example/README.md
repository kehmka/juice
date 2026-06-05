# juice_sync example

An offline outbox you can drive by hand, built with Juice primitives only.

Uses an `InMemorySyncStore`, a fake `DemoExecutor` (`ok` succeeds, `flaky` fails
once then succeeds, `bad` is a permanent dead-letter), and a manual online toggle
— so it runs with **no backend**.

Try it:
- Flip **offline**, enqueue a few — they queue durably (in memory here).
- Flip **online** — the queue auto-flushes.
- Enqueue **flaky** — watch it retry after a backoff.
- Enqueue **bad** — it dead-letters; tap refresh to `retryFailed`, or delete to
  `discard`.

Each tile binds its own `sync:mutation:<id>`; the status bar binds `sync:status`.

For a real app, swap `InMemorySyncStore` for `StorageSyncStore(storageBloc)` and
the demo executor for an adapter over your API (see the package README).

## Run

```bash
flutter run
```
