# github_issue_sync

[![Gem Version](https://img.shields.io/gem/v/github_issue_sync)](https://rubygems.org/gems/github_issue_sync)

Export GitHub issues to CSV and sync edits back to GitHub.

`github_issue_sync` provides two classes:

- **`GithubIssueSync::IssueExporter`** — fetches issues from a GitHub repository
  and writes them to a CSV file suitable for editing in Google Sheets.
- **`GithubIssueSync::IssueSyncer`** — reads that CSV back and pushes any changes
  (title, state, body, labels) to GitHub, and creates new issues for rows that
  have no issue number.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "github_issue_sync"
```

Or install it directly:

```sh
gem install github_issue_sync
```

## Requirements

- Ruby >= 3.1
- A [GitHub personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
  with `repo` scope (or `public_repo` for public repositories).

## Usage

### Export issues to CSV

```ruby
require "github_issue_sync"

exporter = GithubIssueSync::IssueExporter.new(
  repo:   "owner/repo",
  token:  ENV["GITHUB_TOKEN"],
  labels: ["qa-feedback"],   # filter by one or more labels
  state:  "open"             # "open", "closed", or "all"
)

# Write to a file
exporter.call(output_path: "tmp/issues.csv")

# Preview without writing (dry-run)
exporter.call(output_path: "tmp/issues.csv", dry_run: true)
```

The CSV columns are:

| Column | Description |
|--------|-------------|
| GitHub Issue # | Issue number |
| State | `open` or `closed` |
| Title | Issue title |
| Type | Extracted from body table or label (e.g. `bug`, `ux`) |
| Priority | Extracted from body table or label (e.g. `High`, `Low`) |
| Section | Page / section from structured body table |
| Element / Feature | Element from structured body table |
| Description | Full issue body |
| Labels | Comma-separated label names |
| URL | Link to the issue on GitHub |

### Sync CSV edits back to GitHub

```ruby
require "github_issue_sync"

syncer = GithubIssueSync::IssueSyncer.new(
  repo:  "owner/repo",
  token: ENV["GITHUB_TOKEN"]
)

# Apply changes
result = syncer.call(csv_path: "tmp/issues.csv")
puts "Updated: #{result[:updated]}, Created: #{result[:created]}"

# Preview without making any API calls (dry-run)
result = syncer.call(csv_path: "tmp/issues.csv", dry_run: true)
puts "Would update: #{result[:would_update]}, Would create: #{result[:would_create]}"
```

The syncer:

- **Updates** existing issues (matched by `GitHub Issue #`) when the title,
  state, body, or label set has changed.
- **Creates** new issues for rows where `GitHub Issue #` is blank.
- **Skips** rows that are identical to the current GitHub state.

### Structured body format

`IssueExporter` recognises a markdown table format in issue bodies and extracts
the **Type**, **Priority**, **Section**, and **Element / Feature** fields:

```markdown
| **Page / Section** | Dashboard |
| **Element / Feature** | Export button |
| **Type** | Bug |
| **Priority** | 🔴 Critical |
```

If a field is not present in the table, the exporter falls back to scanning
label names (e.g. a `high-priority` label maps to `High`).

## CLI

After installing the gem the `github-issue-sync` command is available.

```sh
# Show version
github-issue-sync version

# Print help
github-issue-sync help
github-issue-sync help export
github-issue-sync help sync
```

### Export

```sh
# Print CSV to stdout
export GITHUB_TOKEN=ghp_...
github-issue-sync export --repo owner/repo

# Write to a file
github-issue-sync export --repo owner/repo --output issues.csv

# Filter by state and labels
github-issue-sync export --repo owner/repo --state closed --labels bug enhancement
```

### Sync

```sh
# Push edits from a CSV back to GitHub
github-issue-sync sync --repo owner/repo --input issues.csv
```

The sync command prints a summary to stderr on completion:

```
Done. Updated: 3, Created: 1
```

## Development

```sh
git clone https://github.com/briancolfer/github_issue_sync
cd github_issue_sync
bundle install
bundle exec rspec
```

Tests use [VCR](https://github.com/vcr/vcr) cassettes so no real GitHub token
is needed. To re-record cassettes against a live repository, delete the
relevant file under `spec/fixtures/vcr_cassettes/` and run the suite with a
valid `GITHUB_TOKEN` in your environment.

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/briancolfer/github_issue_sync).

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).
