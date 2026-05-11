# frozen_string_literal: true

require_relative "../spec_helper"
require "github_issue_sync"

RSpec.describe GithubIssueSync::CLI do
  # Invoke the CLI without debug mode so Thor's own error handling
  # (required-option validation, unknown commands) turns into SystemExit.
  def run(*args)
    described_class.start(args)
  end

  # Replace $stdout during the block and return captured content.
  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end

  # Replace $stderr during the block and return captured content.
  def capture_stderr
    old = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old
  end

  # -----------------------------------------------------------------------
  # version
  # -----------------------------------------------------------------------
  describe "version" do
    it "prints the gem version" do
      output = capture_stdout { run("version") }
      expect(output.chomp).to eq(GithubIssueSync::VERSION)
    end
  end

  # -----------------------------------------------------------------------
  # help
  # -----------------------------------------------------------------------
  describe "help" do
    it "lists all available commands" do
      output = capture_stdout { run("help") }
      expect(output).to include("export")
      expect(output).to include("sync")
      expect(output).to include("version")
    end
  end

  # -----------------------------------------------------------------------
  # export
  # -----------------------------------------------------------------------
  describe "export" do
    let(:exporter_double) { instance_double(GithubIssueSync::IssueExporter) }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GITHUB_TOKEN").and_return("test-token")
      allow(GithubIssueSync::IssueExporter).to receive(:new).and_return(exporter_double)
      allow(exporter_double).to receive(:call)
    end

    context "when GITHUB_TOKEN is missing" do
      before { allow(ENV).to receive(:[]).with("GITHUB_TOKEN").and_return(nil) }

      it "exits with a non-zero status" do
        expect {
          capture_stderr { run("export", "--repo", "owner/repo") }
        }.to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      end

      it "shows a helpful error message mentioning GITHUB_TOKEN" do
        err = capture_stderr do
          run("export", "--repo", "owner/repo")
        rescue SystemExit
          nil
        end
        expect(err).to include("GITHUB_TOKEN")
      end
    end

    context "when --repo is missing" do
      it "exits with a non-zero status" do
        expect {
          capture_stderr { run("export") }
        }.to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      end
    end

    context "with required options" do
      it "builds an IssueExporter with the correct arguments" do
        capture_stdout { run("export", "--repo", "owner/repo") }
        expect(GithubIssueSync::IssueExporter).to have_received(:new).with(
          repo:   "owner/repo",
          token:  "test-token",
          labels: ["qa-feedback"],
          state:  "open"
        )
      end

      it "calls the exporter" do
        capture_stdout { run("export", "--repo", "owner/repo") }
        expect(exporter_double).to have_received(:call)
      end
    end

    context "without --output (stdout mode)" do
      it "does not pass an output_path to the exporter" do
        # Run without capturing so $stdout stays the real IO — the exporter double
        # is stubbed and produces no output, so nothing actually hits the terminal.
        run("export", "--repo", "owner/repo")
        expect(exporter_double).to have_received(:call) do |**kwargs|
          expect(kwargs).not_to have_key(:output_path)
        end
      end
    end

    context "with --output PATH" do
      it "passes the output path to the exporter" do
        run("export", "--repo", "owner/repo", "--output", "issues.csv")
        expect(exporter_double).to have_received(:call).with(
          hash_including(output_path: "issues.csv")
        )
      end
    end

    context "with --state closed" do
      it "forwards the state option to IssueExporter" do
        capture_stdout { run("export", "--repo", "owner/repo", "--state", "closed") }
        expect(GithubIssueSync::IssueExporter).to have_received(:new).with(
          hash_including(state: "closed")
        )
      end
    end
  end

  # -----------------------------------------------------------------------
  # sync
  # -----------------------------------------------------------------------
  describe "sync" do
    let(:syncer_double) { instance_double(GithubIssueSync::IssueSyncer) }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GITHUB_TOKEN").and_return("test-token")
      allow(GithubIssueSync::IssueSyncer).to receive(:new).and_return(syncer_double)
      allow(syncer_double).to receive(:call).and_return({ updated: 0, created: 0 })
    end

    context "when GITHUB_TOKEN is missing" do
      before { allow(ENV).to receive(:[]).with("GITHUB_TOKEN").and_return(nil) }

      it "exits with a non-zero status" do
        expect {
          capture_stderr { run("sync", "--repo", "owner/repo", "--input", "issues.csv") }
        }.to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      end
    end

    context "when --repo is missing" do
      it "exits with a non-zero status" do
        expect {
          capture_stderr { run("sync", "--input", "issues.csv") }
        }.to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      end
    end

    context "when --input is missing" do
      it "exits with a non-zero status" do
        expect {
          capture_stderr { run("sync", "--repo", "owner/repo") }
        }.to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      end
    end

    context "with all required options" do
      it "builds an IssueSyncer with repo and token" do
        run("sync", "--repo", "owner/repo", "--input", "issues.csv")
        expect(GithubIssueSync::IssueSyncer).to have_received(:new).with(
          repo:  "owner/repo",
          token: "test-token"
        )
      end

      it "calls the syncer with the CSV input path" do
        run("sync", "--repo", "owner/repo", "--input", "issues.csv")
        expect(syncer_double).to have_received(:call).with(csv_path: "issues.csv")
      end
    end
  end

  # -----------------------------------------------------------------------
  # unknown command
  # -----------------------------------------------------------------------
  describe "bogus (unknown command)" do
    it "exits with a non-zero status" do
      expect {
        capture_stderr { run("bogus") }
      }.to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
    end
  end
end
