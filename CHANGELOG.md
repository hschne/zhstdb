# Changelog

This project follows [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-07-31

### Added

- FZF-backed history search with directory scopes, previews, sorting, and directory jumping.
- Query filters for hosts, directories, sessions, dates, exit statuses, and exact matches.
- Safe deletion of matching history through `histdb --forget`.
- Integration tests, formatting checks, and continuous integration.

### Changed

- Reworked the plugin into focused recording, querying, and interactive-search modules.
- Updated new databases to schema version 2 with WAL mode.
- Renamed the fork and plugin entry point to `zhstdb`.

### Removed

- Database migration support.
- Git-based database merging and synchronization.

[1.0.0]: https://github.com/hschne/zhstdb/releases/tag/v1.0.0
