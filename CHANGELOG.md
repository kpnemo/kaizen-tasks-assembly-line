# Changelog

All notable changes to this repository are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Facilitator runbook (`docs/runbook.md`): pre-session checklists, the Part 1 minute-by-minute table, gate scripts, a failure page, rollback, and the Part 2/3 handoffs.

### Changed

- `docs/cicd-log.md`: recorded the IaC apply for `api` and `web` in staging and production (Task 8), the wait-for-CI observation of a gated staging deploy (Task 9, V4), the public domain, proxy and health verification (Task 10, L3-M1), and branch protection on `develop` (`ci`) and `main` (`ci`+`promote`) in both app repos (Task 11).

### Fixed

- Railway setup doc: status and branch read-backs use fields the CLI actually emits; rollback section no longer presents `redeploy` as a rollback.
