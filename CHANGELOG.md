# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-11

### Added
- `GithubIssueSync::IssueExporter` — fetch GitHub issues by label/state and write to CSV or stdout.
- `GithubIssueSync::IssueSyncer` — read a CSV and push edits (title, state, body, labels) back to GitHub; create new issues for blank-numbered rows.
- `GithubIssueSync::IssueRow` — value object that maps between GitHub API responses and CSV columns; extracts Type, Priority, Section and Element from structured markdown body tables.
- `github-issue-sync` CLI (Thor-based) with `version`, `export`, and `sync` commands.
- RSpec test suite with VCR cassettes; no real GitHub token required to run tests.
