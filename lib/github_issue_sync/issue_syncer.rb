# frozen_string_literal: true

require "octokit"
require "csv"
require "github_issue_sync/issue_row"

module GithubIssueSync
  # Reads a QA CSV (produced by IssueExporter or the v2 template) and:
  #   • Updates existing GitHub issues whose title, state, body, or labels changed.
  #   • Creates new issues for rows where "GitHub Issue #" is blank.
  #   • Skips rows that are identical to the current GitHub state.
  #
  # Usage:
  #   syncer = GithubIssueSync::IssueSyncer.new(repo: "owner/repo", token: ENV["GITHUB_TOKEN"])
  #   result = syncer.call(csv_path: "tmp/gh-issues-export.csv")
  #   result = syncer.call(csv_path: "...", dry_run: true, io: $stdout)
  class IssueSyncer
    def initialize(repo:, token:)
      @repo  = repo
      @token = token
    end

    # @param csv_path [String]  Path to the CSV to sync.
    # @param dry_run  [Boolean] When true, print intended actions but make no API calls.
    # @param io       [IO]      Output stream for dry-run / summary (default $stdout).
    # @return [Hash]  Counts: { updated:, created: } or { would_update:, would_create: }
    def call(csv_path:, dry_run: false, io: $stdout)
      rows = load_csv(csv_path)

      # Split into existing (have a number) and new (no number).
      existing_rows, new_rows = rows.partition { |r| r["GitHub Issue #"].to_s.strip != "" }

      # Fetch current state of all referenced issues in one pass so we can diff.
      live_issues = fetch_live_issues(existing_rows.map { |r| r["GitHub Issue #"].to_i })

      updated = 0
      created = 0
      would_update = 0
      would_create = 0

      existing_rows.each do |row|
        number = row["GitHub Issue #"].to_i
        live   = live_issues[number]
        next unless live  # issue not found on GitHub — skip silently

        if changed?(row, live)
          if dry_run
            io.puts "DRY-RUN UPDATE ##{number}: #{row['Title']}"
            would_update += 1
          else
            patch_issue(number, row)
            updated += 1
          end
        end
        # else: nothing changed — skip
      end

      new_rows.each do |row|
        if dry_run
          io.puts "DRY-RUN CREATE: #{row['Title']}"
          would_create += 1
        else
          post_issue(row)
          created += 1
        end
      end

      if dry_run
        { would_update: would_update, would_create: would_create }
      else
        { updated: updated, created: created }
      end
    end

    private

    def client
      @client ||= Octokit::Client.new(access_token: @token)
    end

    def load_csv(path)
      CSV.read(path, headers: true).map do |csv_row|
        IssueRow.from_csv_row(csv_row)
      end
    end

    # Fetch each referenced issue individually (acceptable for small QA CSVs).
    def fetch_live_issues(numbers)
      numbers.each_with_object({}) do |number, hash|
        issue = client.issue(@repo, number)
        hash[number] = IssueRow.from_github(issue)
      rescue Octokit::NotFound
        # Issue deleted on GitHub — skip without raising.
      end
    end

    # Detect meaningful changes: title, state, body (description), or label set.
    def changed?(csv_row, live_row)
      csv_row["Title"]       != live_row["Title"]       ||
        csv_row["State"]       != live_row["State"]       ||
        csv_row["Description"] != live_row["Description"] ||
        normalize_labels(csv_row["Labels"]) != normalize_labels(live_row["Labels"])
    end

    def normalize_labels(label_string)
      label_string.to_s.split(",").map(&:strip).sort
    end

    def patch_issue(number, row)
      client.update_issue(@repo, number,
        title:  row["Title"],
        state:  row["State"],
        body:   row["Description"],
        labels: normalize_labels(row["Labels"]))
    end

    def post_issue(row)
      labels = normalize_labels(row["Labels"])
      labels |= [ "qa-feedback" ]  # always include the qa-feedback label

      client.create_issue(@repo,
        row["Title"],
        row["Description"],
        labels: labels)
    end
  end
end
