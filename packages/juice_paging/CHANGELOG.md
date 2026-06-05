# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-28

### Added

- Initial release.
- **`PagingBloc<T>`** — generic paged / infinite-scroll list state: load first
  page, `loadMore` (append), `refresh` (replace), `retry`.
- **`PageFetcher<T>`** — cursor-based seam (`fetch(cursor)` → `PageResult`); the
  opaque cursor supports offset, token, or cursor pagination.
- **In-flight guard** — overlapping loads are ignored, so a scroll listener can
  fire `loadMore` freely.
- **Error handling** — a failed load keeps existing items + cursor; `retry`
  resumes the right page (first vs next).
- **Rebuild groups** — `paging:items`, `paging:status`.
