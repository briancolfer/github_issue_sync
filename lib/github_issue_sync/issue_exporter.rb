# frozen_string_literal: true

require "octokit"
require "csv"
require "qa_tools/issue_row"

module QaTools
  # Fetches GitHub issues matching the given filters and writes them to a CSV
  # that QA engineers can open in Google Sheets.
  #
  # Usage:
  #   exporter = QaTools::IssueExporter.new(
  #     repo:   "owner/repo",
  #     token:  ENV["GITHUB_TOKEN"],
  #     labels: ["qa-feedback"],
  #     state:  "open"
  #   )
  #   exporter.call(output_path: "tmp/gh-issues-export.csv")
  #   exporter.call(output_path: "tmp/gh-issues-export.csv", dry_run: true, io: $stdout)
  class IssueExporter
    PER_PAGE = 100

    def initialize(repo:, token:, labels: [ "qa-feedback" ], state: "open")
      @repo   = repo
      @token  = token
      @labels = labels
      @state  = state
    end

    # @param output_path [String]  Path to write the CSV file.
    # @param dry_run     [Boolean] When true, print to io instead of writing file.
    # @param io          [IO]      Output stream for dry-run (default $stdout).
    def call(output_path:, dry_run: false, io: $stdout)
      issues = fetch_all_issues
      rows   = issues.map { |i| IssueRow.from_github(i) }

      if dry_run
        print_preview(rows, io)
      else
        write_csv(rows, output_path)
        io.puts "Exported #{rows.size} issue(s) to #{output_path}" if io.respond_to?(:puts)
      end
    end

    private

    def client
      @client ||= Octokit::Client.new(access_token: @token)
    end

    # Paginate through all matching issues, filtering out pull requests.
    def fetch_all_issues
      issues   = []
      page     = 1
      options  = {
        labels:   @labels.join(","),
        state:    @state,
        per_page: PER_PAGE
      }

      loop do
        batch = client.list_issues(@repo, options.merge(page: page))
        break if batch.empty?

        # GitHub's issue endpoint returns PRs too; skip them.
        issues.concat(batch.reject { |i| i.respond_to?(:pull_request) && i.pull_request })
        break if batch.size < PER_PAGE

        page += 1
      end

      issues
    end

    def write_csv(rows, path)
      CSV.open(path, "w") do |csv|
        csv << IssueRow::COLUMNS
        rows.each { |row| csv << row.values }
      end
    end

    def print_preview(rows, io)
      io.puts IssueRow::COLUMNS.join(", ")
      io.puts "-" * 80
      rows.each do |row|
        io.puts row.values.map { |v| v.to_s.gsub(/\s+/, " ")[0, 60] }.join(" | ")
      end
    end
  end
end
