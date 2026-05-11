# frozen_string_literal: true

require_relative "lib/github_issue_sync/version"

Gem::Specification.new do |spec|
  spec.name    = "github_issue_sync"
  spec.version = GithubIssueSync::VERSION
  spec.authors = ["Brian Colfer"]
  spec.summary = "Export GitHub issues to CSV and sync changes back to GitHub."
  spec.description = <<~DESC
    github_issue_sync provides two classes — IssueExporter and IssueSyncer — that
    let you download GitHub issues into a CSV (suitable for Google Sheets) and push
    edits or new rows back to GitHub.
  DESC
  spec.homepage = "https://github.com/briancolfer/github_issue_sync_extract"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files         = Dir["lib/**/*.rb", "exe/*", "LICENSE", "README.md"]
  spec.bindir        = "exe"
  spec.executables   = ["github-issue-sync"]
  spec.require_paths = ["lib"]

  spec.add_dependency "csv",     "~> 3.0"
  spec.add_dependency "octokit", "~> 9.0"
  spec.add_dependency "thor",    "~> 1.0"
end
