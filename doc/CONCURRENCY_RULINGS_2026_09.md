# Concurrency mode rulings — examples and teaching code (2026-09-30)

2.0 docket item B, step 1. **SIGNED by Kevin 2026-10-07 ("as recommended")
and APPLIED the same day** — every site below now declares the mode in this
table; the 58 core test sites and the two built-in `UpdateEvent` sites
declare `concurrent`; 25 teaching snippets in the docs declare the mode the
same rules give (loads, fetches and connections `droppable`, mutations
`sequential`). `juice_missing_concurrency_mode` is ON in the five canary
apps (it fired on 9 bare sites in notes_app before the sweep, zero after)
and the `lint:juice` gate enforces it. Every builder site in the family ran
`concurrent` before this; 2.0 makes the mode a required parameter. The
rulings were made from what each use case does.

**Gate honesty:** the five `juice_examples` apps have NO test suites, so
the 113 behaviour changes in them are covered only by analysis and the
lint gate. The root showcase (24 tests), the network and auth_network
examples, core (515) and the benchmarks (17) are green.

121 sites: 90 sequential, 23 droppable, 8 concurrent.

## The rules applied

| rule | mode | when |
|---|---|---|
| mutate, no await | `sequential` | the use case reads and writes bloc state with no `await`. Atomic either way; ruled sequential because the family's own packages rule these sequential (47 of 55 such sites) and it stays correct if an `await` is added later |
| mutate across an await | `sequential` | persist-then-write, or append to a list: order matters and the read-before-await race is impossible |
| latest input wins | `sequential` | search, filter, select, load-by-id. `droppable` would drop the NEWER input; `concurrent` lets an older response land last. Sequential runs every request and finishes on the latest. **These are the consumers `restartable` (#3) was waiting for** |
| exclusive flow | `droppable` | init, load, refresh, submit, checkout: a second one while the first runs is redundant |
| independent | `concurrent` | nothing shared to order; stated per site |

## What changes at run time

Every site runs `concurrent` today, so every ruling other than `concurrent`
changes behaviour in the example it touches:

- `sequential` queues same-type events and runs the whole use case, its
  emit included, behind the previous one. A use case with no `await` emits
  one microtask later than it does today.
- `droppable` drops a same-type event that arrives while one is running.
- Gate: each app's own test suite, plus the juice_lint gate with the
  missing-mode rule ON reporting zero.

## Judgment calls worth your eye

1. **Latest-input-wins ruled `sequential`**, not `concurrent` with a stale
   guard. It wastes the superseded requests but cannot show stale data.
2. **`ManualSaveEvent` sequential, not droppable**: a save asked for during
   a save reads newer content and must still run.
3. **`AutoSaveEvent` and `TickEvent` concurrent**: `execute` only arms a
   timer; the mode has nothing to order.
4. **Load-more `droppable`** leaves the hand-rolled `isLoadingMore` guard in
   place (it also checks `hasReachedEnd`). Removing the redundant half is a
   separate change.
5. **`UploadFileEvent` droppable**: the state holds one file.
6. **The coalescing demo stays `concurrent`**: overlap is what it shows.
7. **Tests (58 sites in core) are not in this table**: they declare
   `concurrent` verbatim, preserving what each test runs today (ruling 4).
   The two core sites (`UpdateEvent` built-ins) declare `concurrent`
   (ruling 2).

## `benchmarks/` — 1 sites (1 concurrent)

| event | builder | awaits | mode | why |
|---|---|---:|---|---|
| `_Ev` <sub>breakdown.dart:67</sub> | Stateful | 0 | **concurrent** | the benchmark measures the path `_FreshBloc` already declares; same mode keeps the two rows comparable |

## Root showcase app (`example/`) — 45 sites (39 sequential, 6 droppable)

| event | builder | awaits | mode | why |
|---|---|---:|---|---|
| `LoginEvent` <sub>blocs/auth/auth_bloc.dart:12</sub> | plain | 1 | **droppable** | exclusive flow: a second one while the first runs is redundant |
| `LogoutEvent` <sub>blocs/auth/auth_bloc.dart:16</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ConnectWebSocketEvent` <sub>blocs/chat/chat_bloc.dart:13</sub> | Stateful | 7 | **droppable** | exclusive flow: a second one while the first runs is redundant |
| `SendMessageEvent` <sub>blocs/chat/chat_bloc.dart:19</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ReceiveMessageEvent` <sub>blocs/chat/chat_bloc.dart:22</sub> | plain | 1 | **sequential** | mutates shared state across an await (persist, then write) |
| `IncrementEvent` <sub>blocs/counter/counter_bloc.dart:13</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `DecrementEvent` <sub>blocs/counter/counter_bloc.dart:16</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ResetEvent` <sub>blocs/counter/counter_bloc.dart:19</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ShowcaseIncrementEvent` <sub>blocs/features_showcase/features_showcase_bloc.dart:25</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ShowcaseDecrementEvent` <sub>blocs/features_showcase/features_showcase_bloc.dart:29</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `SimulateApiCallEvent` <sub>blocs/features_showcase/features_showcase_bloc.dart:34</sub> | plain | 1 | **sequential** | mutates shared state across an await (persist, then write) |
| `ValidateInputEvent` <sub>blocs/features_showcase/features_showcase_bloc.dart:39</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `UpdateMessageEvent` <sub>blocs/features_showcase/features_showcase_bloc.dart:44</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ClearErrorEvent` <sub>blocs/features_showcase/features_showcase_bloc.dart:49</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ShowcaseResetEvent` <sub>blocs/features_showcase/features_showcase_bloc.dart:53</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `UploadFileEvent` <sub>blocs/file_upload/src/file_upload_bloc.dart:10</sub> | plain | 1 | **droppable** | one upload at a time: the state holds a single file; cancel, then send again |
| `SubmitFormEvent` <sub>blocs/form/form_bloc.dart:10</sub> | plain | 1 | **droppable** | exclusive flow: a double submit must not run twice |
| `StartDemoEvent` <sub>blocs/lifecycle_demo/lifecycle_demo_bloc.dart:31</sub> | plain | 1 | **droppable** | exclusive flow: a second one while the first runs is redundant |
| `EndDemoEvent` <sub>blocs/lifecycle_demo/lifecycle_demo_bloc.dart:35</sub> | plain | 1 | **droppable** | exclusive flow: a second one while the first runs is redundant |
| `ToggleSlowCleanupEvent` <sub>blocs/lifecycle_demo/lifecycle_demo_bloc.dart:39</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `UpdateTaskProgressEvent` <sub>blocs/lifecycle_demo/lifecycle_demo_bloc.dart:43</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `TaskCompletedEvent` <sub>blocs/lifecycle_demo/lifecycle_demo_bloc.dart:47</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `CancelAllTasksEvent` <sub>blocs/lifecycle_demo/lifecycle_demo_bloc.dart:51</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `AddLogEvent` <sub>blocs/lifecycle_demo/lifecycle_demo_bloc.dart:55</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ScopeEndingEvent` <sub>blocs/lifecycle_demo/lifecycle_demo_bloc.dart:59</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ScopeEndedEvent` <sub>blocs/lifecycle_demo/lifecycle_demo_bloc.dart:63</sub> | plain | 1 | **sequential** | mutates shared state across an await (persist, then write) |
| `UpdateDemoStateEvent` <sub>blocs/lifecycle_demo/lifecycle_demo_bloc.dart:67</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ResetDemoEvent` <sub>blocs/lifecycle_demo/lifecycle_demo_bloc.dart:71</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `NextPageEvent` <sub>blocs/onboard/onboard_bloc.dart:9</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `StateRelayedEvent` <sub>blocs/relay_demo/dest_bloc.dart:13</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `StatusUpdatingEvent` <sub>blocs/relay_demo/dest_bloc.dart:17</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `StatusWaitingEvent` <sub>blocs/relay_demo/dest_bloc.dart:21</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `StatusFailedEvent` <sub>blocs/relay_demo/dest_bloc.dart:25</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ClearLogEvent` <sub>blocs/relay_demo/dest_bloc.dart:29</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `IncrementSourceEvent` <sub>blocs/relay_demo/source_bloc.dart:13</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `DecrementSourceEvent` <sub>blocs/relay_demo/source_bloc.dart:17</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `SimulateAsyncEvent` <sub>blocs/relay_demo/source_bloc.dart:21</sub> | plain | 1 | **sequential** | mutates shared state across an await (persist, then write) |
| `SimulateErrorEvent` <sub>blocs/relay_demo/source_bloc.dart:25</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ResetSourceEvent` <sub>blocs/relay_demo/source_bloc.dart:29</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ToggleTemperatureUnitEvent` <sub>blocs/settings/settings_bloc.dart:10</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `AddTodoEvent` <sub>blocs/todo/todo_bloc.dart:14</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `UpdateTodoEvent` <sub>blocs/todo/todo_bloc.dart:17</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `RemoveTodoEvent` <sub>blocs/todo/todo_bloc.dart:20</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ToggleTodoEvent` <sub>blocs/todo/todo_bloc.dart:23</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `FetchWeatherEvent` <sub>blocs/weather/weather_bloc.dart:10</sub> | plain | 1 | **sequential** | latest input must win; `restartable` is the right mode when it exists (#3) — `droppable` would drop the NEWER input, `concurrent` lets an older response land last |

## `packages/juice/example` — 3 sites (2 sequential, 1 concurrent)

| event | builder | awaits | mode | why |
|---|---|---:|---|---|
| `IncrementEvent` <sub>packages/juice/example/example.dart:46</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `DecrementEvent` <sub>packages/juice/example/example.dart:50</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `RefreshRowEvent` <sub>packages/juice/example/example.dart:155</sub> | plain | 1 | **concurrent** | independent per row: `guardEntity` tracks each row's own status |

## `packages/juice_auth_network/example` — 1 sites (1 droppable)

| event | builder | awaits | mode | why |
|---|---|---:|---|---|
| `LoadProfileEvent` <sub>profile_bloc.dart:114</sub> | plain | 1 | **droppable** | exclusive flow: a second one while the first runs is redundant |

## `juice_examples` · chat_app — 7 sites (6 sequential, 1 droppable)

| event | builder | awaits | mode | why |
|---|---|---:|---|---|
| `LoadMessagesEvent` <sub>blocs/chat_bloc.dart:21</sub> | plain | 1 | **sequential** | latest input must win; `restartable` is the right mode when it exists (#3) — `droppable` would drop the NEWER input, `concurrent` lets an older response land last |
| `SendMessageEvent` <sub>blocs/chat_bloc.dart:25</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ReceiveMessageEvent` <sub>blocs/chat_bloc.dart:29</sub> | plain | 1 | **sequential** | mutates shared state across an await (persist, then write) |
| `UpdateTypingEvent` <sub>blocs/chat_bloc.dart:33</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `LoadContactsEvent` <sub>blocs/contacts_bloc.dart:15</sub> | plain | 0 | **droppable** | exclusive flow: a second one while the first runs is redundant |
| `UpdateContactStatusEvent` <sub>blocs/contacts_bloc.dart:20</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `UpdateContactLastMessageEvent` <sub>blocs/contacts_bloc.dart:24</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |

## `juice_examples` · dashboard — 4 sites (3 droppable, 1 sequential)

| event | builder | awaits | mode | why |
|---|---|---:|---|---|
| `LoadAnalyticsEvent` <sub>blocs/analytics_bloc.dart:12</sub> | plain | 1 | **droppable** | exclusive flow: a second one while the first runs is redundant |
| `FilterDataEvent` <sub>blocs/analytics_bloc.dart:17</sub> | plain | 1 | **sequential** | latest input must win; `restartable` is the right mode when it exists (#3) — `droppable` would drop the NEWER input, `concurrent` lets an older response land last |
| `LoadDashboardEvent` <sub>blocs/dashboard_bloc.dart:12</sub> | plain | 1 | **droppable** | exclusive flow: a second one while the first runs is redundant |
| `RefreshStatsEvent` <sub>blocs/dashboard_bloc.dart:17</sub> | plain | 1 | **droppable** | exclusive flow: a second one while the first runs is redundant |

## `juice_examples` · ecommerce — 10 sites (6 sequential, 4 droppable)

| event | builder | awaits | mode | why |
|---|---|---:|---|---|
| `LoadCartEvent` <sub>blocs/cart_bloc.dart:13</sub> | plain | 1 | **droppable** | exclusive flow: a second one while the first runs is redundant |
| `AddToCartEvent` <sub>blocs/cart_bloc.dart:18</sub> | plain | 2 | **sequential** | mutates shared state across an await (persist, then write) |
| `RemoveFromCartEvent` <sub>blocs/cart_bloc.dart:22</sub> | plain | 2 | **sequential** | mutates shared state across an await (persist, then write) |
| `UpdateCartQuantityEvent` <sub>blocs/cart_bloc.dart:26</sub> | plain | 1 | **sequential** | mutates shared state across an await (persist, then write) |
| `CheckoutEvent` <sub>blocs/cart_bloc.dart:30</sub> | plain | 2 | **droppable** | exclusive flow: a double checkout must not run twice |
| `LoadProductsEvent` <sub>blocs/products_bloc.dart:16</sub> | plain | 1 | **sequential** | latest input must win; `restartable` is the right mode when it exists (#3) — `droppable` would drop the NEWER input, `concurrent` lets an older response land last |
| `LoadCategoriesEvent` <sub>blocs/products_bloc.dart:21</sub> | plain | 1 | **droppable** | exclusive flow: a second one while the first runs is redundant |
| `LoadMoreProductsEvent` <sub>blocs/products_bloc.dart:26</sub> | plain | 1 | **droppable** | exclusive flow: replaces the hand-rolled `isLoadingMore` guard |
| `SearchProductsEvent` <sub>blocs/products_bloc.dart:30</sub> | plain | 1 | **sequential** | latest input must win; `restartable` is the right mode when it exists (#3) — `droppable` would drop the NEWER input, `concurrent` lets an older response land last |
| `LoadProductDetailEvent` <sub>blocs/products_bloc.dart:34</sub> | plain | 1 | **sequential** | latest input must win; `restartable` is the right mode when it exists (#3) — `droppable` would drop the NEWER input, `concurrent` lets an older response land last |

## `juice_examples` · notes_app — 18 sites (14 sequential, 3 droppable, 1 concurrent)

| event | builder | awaits | mode | why |
|---|---|---:|---|---|
| `InitEditorEvent` <sub>blocs/editor/editor_bloc.dart:27</sub> | Inline | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `UpdateContentEvent` <sub>blocs/editor/editor_bloc.dart:52</sub> | Inline | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ChangeEditorColorEvent` <sub>blocs/editor/editor_bloc.dart:76</sub> | Inline | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `AutoSaveEvent` <sub>blocs/editor/editor_bloc.dart:94</sub> | Stateful | 1 | **concurrent** | execute only re-arms a debounce timer; every event must be seen and there is nothing to order (the save reads state when the timer fires) |
| `ManualSaveEvent` <sub>blocs/editor/editor_bloc.dart:100</sub> | plain | 2 | **sequential** | a save requested during a save must still run: it reads the newer content |
| `LoadNotesEvent` <sub>blocs/notes/notes_bloc.dart:29</sub> | plain | 4 | **droppable** | exclusive flow: a second one while the first runs is redundant |
| `SaveNoteEvent` <sub>blocs/notes/notes_bloc.dart:36</sub> | plain | 1 | **sequential** | mutates shared state across an await (persist, then write) |
| `SearchNotesEvent` <sub>blocs/notes/notes_bloc.dart:44</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `TogglePinEvent` <sub>blocs/notes/notes_bloc.dart:50</sub> | Inline | 1 | **sequential** | mutates shared state across an await (persist, then write) |
| `ChangeNoteColorEvent` <sub>blocs/notes/notes_bloc.dart:69</sub> | Inline | 1 | **sequential** | mutates shared state across an await (persist, then write) |
| `MoveToTrashEvent` <sub>blocs/notes/notes_bloc.dart:88</sub> | plain | 2 | **sequential** | mutates shared state across an await (persist, then write) |
| `RestoreFromTrashEvent` <sub>blocs/notes/notes_bloc.dart:94</sub> | plain | 2 | **sequential** | mutates shared state across an await (persist, then write) |
| `EmptyTrashEvent` <sub>blocs/notes/notes_bloc.dart:100</sub> | plain | 1 | **droppable** | exclusive bulk operation |
| `PermanentDeleteEvent` <sub>blocs/notes/notes_bloc.dart:106</sub> | plain | 1 | **sequential** | mutates shared state across an await (persist, then write) |
| `SettingsChangedEvent` <sub>blocs/notes/notes_bloc.dart:112</sub> | Inline | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `LoadSettingsEvent` <sub>blocs/settings/settings_bloc.dart:25</sub> | plain | 2 | **droppable** | exclusive flow: a second one while the first runs is redundant |
| `ToggleViewModeEvent` <sub>blocs/settings/settings_bloc.dart:32</sub> | Inline | 1 | **sequential** | mutates shared state across an await (persist, then write) |
| `ChangeSortOrderEvent` <sub>blocs/settings/settings_bloc.dart:49</sub> | Inline | 1 | **sequential** | mutates shared state across an await (persist, then write) |

## `juice_examples` · social_feed — 6 sites (3 droppable, 3 sequential)

| event | builder | awaits | mode | why |
|---|---|---:|---|---|
| `LoadFeedEvent` <sub>blocs/feed_bloc.dart:18</sub> | plain | 1 | **droppable** | exclusive flow: a second one while the first runs is redundant |
| `LoadMoreEvent` <sub>blocs/feed_bloc.dart:23</sub> | plain | 1 | **droppable** | exclusive flow: replaces the hand-rolled `isLoadingMore` guard |
| `LikePostEvent` <sub>blocs/feed_bloc.dart:27</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `AddCommentEvent` <sub>blocs/feed_bloc.dart:31</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `SelectPostEvent` <sub>blocs/feed_bloc.dart:35</sub> | plain | 1 | **sequential** | latest input must win; `restartable` is the right mode when it exists (#3) — `droppable` would drop the NEWER input, `concurrent` lets an older response land last |
| `LoadProfileEvent` <sub>blocs/profile_bloc.dart:14</sub> | plain | 1 | **droppable** | exclusive flow: a second one while the first runs is redundant |

## `packages/juice_network/example` — 16 sites (11 sequential, 4 concurrent, 1 droppable)

| event | builder | awaits | mode | why |
|---|---|---:|---|---|
| `FireRequestEvent` <sub>blocs/coalesce_bloc.dart:171</sub> | plain | 1 | **concurrent** | the demo IS overlapping same-type requests: coalescing only shows when they run together |
| `FireBurstEvent` <sub>blocs/coalesce_bloc.dart:175</sub> | plain | 1 | **concurrent** | the demo IS overlapping same-type requests: coalescing only shows when they run together |
| `ResetCoalesceEvent` <sub>blocs/coalesce_bloc.dart:179</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ConfigureInterceptorsEvent` <sub>blocs/interceptors_bloc.dart:211</sub> | plain | 1 | **sequential** | mutates shared state across an await (persist, then write) |
| `ToggleLoggingEvent` <sub>blocs/interceptors_bloc.dart:216</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ToggleAuthEvent` <sub>blocs/interceptors_bloc.dart:220</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `ToggleTimingEvent` <sub>blocs/interceptors_bloc.dart:224</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `MakeRequestEvent` <sub>blocs/interceptors_bloc.dart:228</sub> | plain | 1 | **concurrent** | independent requests; the use case writes no state |
| `MakeFailingRequestEvent` <sub>blocs/interceptors_bloc.dart:232</sub> | plain | 1 | **concurrent** | independent requests; the use case writes no state |
| `ClearLogsEvent` <sub>blocs/interceptors_bloc.dart:236</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `AddLogEvent` <sub>blocs/interceptors_bloc.dart:240</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `LoadPostsEvent` <sub>blocs/posts_bloc.dart:238</sub> | plain | 1 | **droppable** | exclusive flow: a second one while the first runs is redundant |
| `SetCachePolicyEvent` <sub>blocs/posts_bloc.dart:243</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `LoadPostDetailEvent` <sub>blocs/posts_bloc.dart:247</sub> | plain | 1 | **sequential** | latest input must win; `restartable` is the right mode when it exists (#3) — `droppable` would drop the NEWER input, `concurrent` lets an older response land last |
| `DeletePostEvent` <sub>blocs/posts_bloc.dart:251</sub> | plain | 1 | **sequential** | mutates shared state across an await (persist, then write) |
| `ClearPostDetailEvent` <sub>blocs/posts_bloc.dart:255</sub> | plain | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |

## `packages/juice_storage/example` — 10 sites (8 sequential, 1 droppable, 1 concurrent)

| event | builder | awaits | mode | why |
|---|---|---:|---|---|
| `UpdateKeyEvent` <sub>blocs/arcade_demo_bloc.dart:37</sub> | Inline | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `UpdateValueEvent` <sub>blocs/arcade_demo_bloc.dart:46</sub> | Inline | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `SelectBackendEvent` <sub>blocs/arcade_demo_bloc.dart:56</sub> | Inline | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `UpdateTtlEvent` <sub>blocs/arcade_demo_bloc.dart:67</sub> | Inline | 0 | **sequential** | mutates bloc state with no await; the family's own packages rule these sequential (47 of 55) |
| `SaveEntryEvent` <sub>blocs/arcade_demo_bloc.dart:78</sub> | plain | 5 | **sequential** | mutates shared state across an await (persist, then write) |
| `ReadEntryEvent` <sub>blocs/arcade_demo_bloc.dart:82</sub> | plain | 4 | **sequential** | mutates shared state across an await (persist, then write) |
| `DeleteEntryEvent` <sub>blocs/arcade_demo_bloc.dart:86</sub> | plain | 4 | **sequential** | mutates shared state across an await (persist, then write) |
| `SpawnBombsEvent` <sub>blocs/arcade_demo_bloc.dart:90</sub> | plain | 2 | **sequential** | mutates shared state across an await (persist, then write) |
| `CleanupCacheEvent` <sub>blocs/arcade_demo_bloc.dart:94</sub> | plain | 1 | **droppable** | exclusive flow: one sweep at a time |
| `TickEvent` <sub>blocs/arcade_demo_bloc.dart:100</sub> | Stateful | 0 | **concurrent** | execute only arms a periodic timer once (`_timer ??=`); nothing to order |
