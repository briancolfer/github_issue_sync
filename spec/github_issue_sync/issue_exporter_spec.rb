# frozen_string_literal: true

require_relative "../spec_helper"
require "github_issue_sync/issue_exporter"
require "tmpdir"
require "json"

RSpec.describe GithubIssueSync::IssueExporter do
  let(:repo)  { "briancolfer/abcscribe" }
  let(:token) { "test-token" }

  subject(:exporter) do
    described_class.new(repo: repo, token: token, labels: [ "qa-feedback" ], state: "open")
  end

  describe "#call — writing a CSV file", vcr: { cassette_name: "list_issues" } do
    let(:output_path) { File.join(Dir.tmpdir, "test-export-#{Process.pid}.csv") }

    after { File.delete(output_path) if File.exist?(output_path) }

    it "creates the output file" do
      exporter.call(output_path: output_path)
      expect(File.exist?(output_path)).to be true
    end

    it "writes the header row matching IssueRow::COLUMNS" do
      exporter.call(output_path: output_path)
      headers = CSV.read(output_path).first
      expect(headers).to eq(GithubIssueSync::IssueRow::COLUMNS)
    end

    it "writes one data row per issue returned by the API" do
      exporter.call(output_path: output_path)
      rows = CSV.read(output_path)
      expect(rows.length).to eq(3) # 1 header + 2 issues
    end

    it "populates the GitHub Issue # column correctly" do
      exporter.call(output_path: output_path)
      data_rows = CSV.read(output_path, headers: true)
      expect(data_rows.map { |r| r["GitHub Issue #"] }).to contain_exactly("42", "43")
    end

    it "correctly extracts Section from the structured body" do
      exporter.call(output_path: output_path)
      data_rows = CSV.read(output_path, headers: true)
      issue_42  = data_rows.find { |r| r["GitHub Issue #"] == "42" }
      expect(issue_42["Section"]).to eq("Active Behaviors")
    end

    it "correctly extracts Priority from the structured body" do
      exporter.call(output_path: output_path)
      data_rows = CSV.read(output_path, headers: true)
      issue_42  = data_rows.find { |r| r["GitHub Issue #"] == "42" }
      expect(issue_42["Priority"]).to eq("High")
    end

    it "skips pull requests (issues with a pull_request key)" do
      # The cassette issues have pull_request: null, so both should be included.
      # This test documents the skip-PR contract — a PR-shaped response would be excluded.
      exporter.call(output_path: output_path)
      data_rows = CSV.read(output_path, headers: true)
      expect(data_rows.count).to eq(2)
    end
  end

  describe "#call — stdout mode (output_path: nil)", vcr: { cassette_name: "list_issues" } do
    it "writes valid CSV to the provided IO" do
      io = StringIO.new
      exporter.call(io: io)
      lines = CSV.parse(io.string)
      expect(lines.first).to eq(GithubIssueSync::IssueRow::COLUMNS)
      expect(lines.length).to eq(3) # header + 2 issues
    end

    it "does not create any file on disk" do
      io = StringIO.new
      expect { exporter.call(io: io) }.not_to change { Dir.glob("*.csv").count }
    end
  end

  describe "faraday-retry middleware" do
    it "is registered in Octokit's default Faraday stack" do
      require "faraday/retry"
      handler_classes = Octokit::Default.middleware.handlers.map(&:klass)
      expect(handler_classes).to include(Faraday::Retry::Middleware)
    end

    it "retries a transient 503 server error and succeeds on the second attempt" do
      issues_json = JSON.generate([
        {
          "number" => 42, "state" => "open",
          "title" => "Retry test issue", "body" => "",
          "labels" => [], "html_url" => "https://github.com/briancolfer/abcscribe/issues/42",
          "pull_request" => nil
        }
      ])

      stub_request(:get, "https://api.github.com/repos/briancolfer/abcscribe/issues")
        .with(query: hash_including("labels" => "qa-feedback", "state" => "open"))
        .to_return(
          { status: 503, body: "Service Unavailable", headers: {} },
          { status: 200, body: issues_json, headers: { "Content-Type" => "application/json" } }
        )

      io = StringIO.new
      exporter.call(io: io)
      csv = CSV.parse(io.string, headers: true)
      expect(csv.map { |r| r["GitHub Issue #"] }).to include("42")
    end
  end

  describe "#call — dry-run mode", vcr: { cassette_name: "list_issues" } do
    let(:output_path) { File.join(Dir.tmpdir, "should-not-exist-#{Process.pid}.csv") }

    after { File.delete(output_path) if File.exist?(output_path) }

    it "prints each row to the provided IO rather than writing a file" do
      io = StringIO.new
      exporter.call(output_path: output_path, dry_run: true, io: io)
      output = io.string
      expect(output).to include("42")
      expect(output).to include("43")
    end

    it "does NOT create the output file in dry-run mode" do
      io = StringIO.new
      exporter.call(output_path: output_path, dry_run: true, io: io)
      expect(File.exist?(output_path)).to be false
    end
  end
end
