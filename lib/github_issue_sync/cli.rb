# frozen_string_literal: true

require "thor"
require_relative "../github_issue_sync"

module GithubIssueSync
  class CLI < Thor
    # Let Thor's required-option and unknown-command errors exit non-zero.
    def self.exit_on_failure?
      true
    end

    # -----------------------------------------------------------------
    # version
    # -----------------------------------------------------------------
    desc "version", "Print the gem version"
    def version
      puts GithubIssueSync::VERSION
    end

    # -----------------------------------------------------------------
    # export
    # -----------------------------------------------------------------
    desc "export", "Export GitHub issues to CSV"
    method_option :repo,
      aliases: "-r", required: true,
      desc: "Repository slug (owner/repo)"
    method_option :state,
      aliases: "-s", default: "open",
      desc: "Issue state: open, closed, or all"
    method_option :labels,
      aliases: "-l", type: :array, default: ["qa-feedback"],
      desc: "Label filters (space-separated)"
    method_option :output,
      aliases: "-o",
      desc: "Output file path (omit to print CSV to stdout)"
    method_option :format,
      aliases: "-f", default: "csv",
      desc: "Output format (currently only csv)"
    def export
      token = require_token!
      exporter = IssueExporter.new(
        repo:   options[:repo],
        token:  token,
        labels: options[:labels],
        state:  options[:state]
      )

      if (path = options[:output])
        exporter.call(output_path: path, io: $stderr)
      else
        exporter.call(io: $stdout)
      end
    end

    # -----------------------------------------------------------------
    # sync
    # -----------------------------------------------------------------
    desc "sync", "Sync CSV edits back to GitHub issues"
    method_option :repo,
      aliases: "-r", required: true,
      desc: "Repository slug (owner/repo)"
    method_option :input,
      aliases: "-i", required: true,
      desc: "Path to the input CSV file"
    method_option :format,
      aliases: "-f", default: "csv",
      desc: "Input format (currently only csv)"
    def sync
      token = require_token!
      syncer = IssueSyncer.new(repo: options[:repo], token: token)
      result = syncer.call(csv_path: options[:input])
      $stderr.puts "Done. Updated: #{result[:updated]}, Created: #{result[:created]}"
    end

    private

    def require_token!
      token = ENV["GITHUB_TOKEN"]
      return token if token && !token.empty?

      abort(
        "Error: GITHUB_TOKEN environment variable is not set.\n" \
        "Hint:  export GITHUB_TOKEN=<your_personal_access_token>"
      )
    end
  end
end
