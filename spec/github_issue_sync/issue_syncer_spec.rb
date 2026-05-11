# frozen_string_literal: true

require_relative "../../qa_tools_helper"
require "qa_tools/issue_syncer"
require "tmpdir"

# Helper to write a minimal CSV file with the IssueRow column layout.
def write_csv(path, rows)
  require "qa_tools/issue_row"
  CSV.open(path, "w") do |csv|
    csv << QaTools::IssueRow::COLUMNS
    rows.each { |r| csv << QaTools::IssueRow::COLUMNS.map { |c| r[c] } }
  end
end

RSpec.describe QaTools::IssueSyncer do
  let(:repo)  { "briancolfer/abcscribe" }
  let(:token) { "test-token" }

  subject(:syncer) { described_class.new(repo: repo, token: token) }

  # A changed issue: same number as cassette issue 42 but title is different.
  let(:changed_row) do
    {
      "GitHub Issue #"    => "42",
      "State"             => "open",
      "Title"             => "Active Behaviors › Archive: Updated title.",
      "Type"              => "UX",
      "Priority"          => "High",
      "Section"           => "Active Behaviors",
      "Element / Feature" => "Archive confirmation dialog",
      "Description"       => "Updated body text.",
      "Labels"            => "qa-feedback, pre-launch, ux",
      "URL"               => "https://github.com/briancolfer/abcscribe/issues/42"
    }
  end

  # An unchanged issue: title and body exactly match what the cassette returns
  # for issue 42 (no API call should be made).
  let(:unchanged_row) do
    {
      "GitHub Issue #"    => "42",
      "State"             => "open",
      "Title"             => "Active Behaviors › Archive: The popup looks like a system dialog.",
      "Type"              => "UX",
      "Priority"          => "High",
      "Section"           => "Active Behaviors",
      "Element / Feature" => "Archive confirmation dialog",
      "Description"       => "The archive popup uses the browser native confirm() dialog.",
      "Labels"            => "qa-feedback, pre-launch, ux",
      "URL"               => "https://github.com/briancolfer/abcscribe/issues/42"
    }
  end

  # A new issue: blank GitHub Issue # → POST
  let(:new_row) do
    {
      "GitHub Issue #"    => "",
      "State"             => "open",
      "Title"             => "New issue from QA spreadsheet",
      "Type"              => "Bug",
      "Priority"          => "Medium",
      "Section"           => "Home Page",
      "Element / Feature" => "Hero copy",
      "Description"       => "Body of the new issue.",
      "Labels"            => "qa-feedback, bug",
      "URL"               => ""
    }
  end

  describe "#call — update a changed issue",
           vcr: { cassette_name: "update_issue", match_requests_on: %i[method uri] } do
    let(:csv_path) { File.join(Dir.tmpdir, "sync-test-#{Process.pid}.csv") }
    after { File.delete(csv_path) if File.exist?(csv_path) }

    it "calls PATCH on the API for the changed row" do
      write_csv(csv_path, [ changed_row ])
      result = syncer.call(csv_path: csv_path)
      expect(result[:updated]).to eq(1)
      expect(result[:created]).to eq(0)
    end
  end

  describe "#call — create a new issue",
           vcr: { cassette_name: "create_issue", match_requests_on: %i[method uri] } do
    let(:csv_path) { File.join(Dir.tmpdir, "sync-test-#{Process.pid}.csv") }
    after { File.delete(csv_path) if File.exist?(csv_path) }

    it "calls POST on the API for a row with no issue number" do
      write_csv(csv_path, [ new_row ])
      result = syncer.call(csv_path: csv_path)
      expect(result[:created]).to eq(1)
      expect(result[:updated]).to eq(0)
    end
  end

  # Shared WebMock stub: returns a live GitHub issue that exactly matches
  # unchanged_row so the syncer sees no diff and makes no PATCH call.
  def stub_get_issue_42_unchanged
    body = JSON.generate(
      number: 42,
      state: "open",
      title: "Active Behaviors \u203a Archive: The popup looks like a system dialog.",
      body: "The archive popup uses the browser native confirm() dialog.",
      labels: [
        { id: 1, name: "qa-feedback", color: "fbca04" },
        { id: 2, name: "pre-launch",  color: "e11d48" },
        { id: 3, name: "ux",          color: "bfd4f2" }
      ],
      html_url: "https://github.com/briancolfer/abcscribe/issues/42"
    )
    stub_request(:get, "https://api.github.com/repos/briancolfer/abcscribe/issues/42")
      .to_return(status: 200,
                 body: body,
                 headers: { "Content-Type" => "application/json" })
  end

  # Shared WebMock stub: returns a live GitHub issue matching changed_row's number
  # (so the syncer can detect a diff) but with the OLD title/body.
  def stub_get_issue_42_old
    body = JSON.generate(
      number: 42,
      state: "open",
      title: "Active Behaviors \u203a Archive: The popup looks like a system dialog.",
      body: "The archive popup uses the browser native confirm() dialog.",
      labels: [
        { id: 1, name: "qa-feedback", color: "fbca04" },
        { id: 2, name: "pre-launch",  color: "e11d48" },
        { id: 3, name: "ux",          color: "bfd4f2" }
      ],
      html_url: "https://github.com/briancolfer/abcscribe/issues/42"
    )
    stub_request(:get, "https://api.github.com/repos/briancolfer/abcscribe/issues/42")
      .to_return(status: 200,
                 body: body,
                 headers: { "Content-Type" => "application/json" })
  end

  describe "#call — skip unchanged rows" do
    let(:csv_path) { File.join(Dir.tmpdir, "sync-test-#{Process.pid}.csv") }
    after { File.delete(csv_path) if File.exist?(csv_path) }

    it "makes no API calls and reports 0 changes when nothing has changed" do
      stub_get_issue_42_unchanged
      write_csv(csv_path, [ unchanged_row ])
      expect { syncer.call(csv_path: csv_path) }.not_to raise_error
    end

    it "returns 0 updated and 0 created for an unchanged row" do
      stub_get_issue_42_unchanged
      write_csv(csv_path, [ unchanged_row ])
      result = syncer.call(csv_path: csv_path)
      expect(result[:updated]).to eq(0)
      expect(result[:created]).to eq(0)
    end
  end

  describe "#call — dry-run mode" do
    let(:csv_path) { File.join(Dir.tmpdir, "sync-test-#{Process.pid}.csv") }
    after { File.delete(csv_path) if File.exist?(csv_path) }

    it "makes no API calls in dry-run mode" do
      stub_get_issue_42_old
      write_csv(csv_path, [ changed_row, new_row ])
      # No PATCH or POST should be made — WebMock would catch it.
      expect { syncer.call(csv_path: csv_path, dry_run: true) }.not_to raise_error
    end

    it "returns the intended action counts without performing them" do
      stub_get_issue_42_old
      write_csv(csv_path, [ changed_row, new_row ])
      result = syncer.call(csv_path: csv_path, dry_run: true)
      expect(result[:would_update]).to eq(1)
      expect(result[:would_create]).to eq(1)
    end

    it "prints a preview to the provided io" do
      stub_get_issue_42_old
      io = StringIO.new
      write_csv(csv_path, [ changed_row, new_row ])
      syncer.call(csv_path: csv_path, dry_run: true, io: io)
      output = io.string
      expect(output).to include("UPDATE")
      expect(output).to include("CREATE")
    end
  end
end
