# frozen_string_literal: true

require_relative "../../qa_tools_helper"
require "qa_tools/issue_row"

RSpec.describe QaTools::IssueRow do
  # A minimal Sawyer::Resource double — just needs [] and .labels
  let(:gh_issue) do
    labels = [
      double("label", name: "qa-feedback"),
      double("label", name: "pre-launch"),
      double("label", name: "ux")
    ]
    double("Sawyer::Resource",
      number: 42,
      state: "open",
      title: "Active Behaviors › Archive: The popup looks like a system dialog.",
      body: <<~BODY,
        ## QA Feedback

        | Field | Value |
        | --- | --- |
        | **Page / Section** | Active Behaviors |
        | **Element / Feature** | Archive confirmation dialog |
        | **Type** | UX |
        | **Priority** | 🟠 High — pre-launch preferred |

        ## Description

        The popup looks like a system dialog.
      BODY
      labels: labels,
      html_url: "https://github.com/briancolfer/abcscribe/issues/42")
  end

  describe "COLUMNS" do
    it "contains the expected column names in order" do
      expect(QaTools::IssueRow::COLUMNS).to eq(%w[
        GitHub\ Issue\ #
        State
        Title
        Type
        Priority
        Section
        Element\ /\ Feature
        Description
        Labels
        URL
      ])
    end
  end

  describe ".from_github" do
    subject(:row) { described_class.from_github(gh_issue) }

    it "captures the issue number" do
      expect(row["GitHub Issue #"]).to eq("42")
    end

    it "captures the state" do
      expect(row["State"]).to eq("open")
    end

    it "captures the title" do
      expect(row["Title"]).to eq("Active Behaviors › Archive: The popup looks like a system dialog.")
    end

    it "extracts Section from the structured body table" do
      expect(row["Section"]).to eq("Active Behaviors")
    end

    it "extracts Element / Feature from the structured body table" do
      expect(row["Element / Feature"]).to eq("Archive confirmation dialog")
    end

    it "extracts Type from the structured body table" do
      expect(row["Type"]).to eq("UX")
    end

    it "extracts Priority from the structured body table (strips emoji prefix)" do
      expect(row["Priority"]).to eq("High")
    end

    it "captures the full body as Description" do
      expect(row["Description"]).to include("The popup looks like a system dialog.")
    end

    it "joins all label names into a comma-separated Labels string" do
      expect(row["Labels"]).to eq("qa-feedback, pre-launch, ux")
    end

    it "captures the HTML URL" do
      expect(row["URL"]).to eq("https://github.com/briancolfer/abcscribe/issues/42")
    end

    context "when the body is NOT in structured format" do
      let(:gh_issue) do
        double("Sawyer::Resource",
          number: 99,
          state: "open",
          title: "Manually created issue",
          body: "Some free-form notes without a table.",
          labels: [],
          html_url: "https://github.com/briancolfer/abcscribe/issues/99")
      end

      it "returns blank Section" do
        expect(row["Section"]).to eq("")
      end

      it "returns blank Element / Feature" do
        expect(row["Element / Feature"]).to eq("")
      end

      it "falls back to blank Type" do
        expect(row["Type"]).to eq("")
      end

      it "falls back to blank Priority" do
        expect(row["Priority"]).to eq("")
      end
    end

    context "when a label is low-priority" do
      let(:gh_issue) do
        double("Sawyer::Resource",
          number: 100,
          state: "open",
          title: "Low priority issue",
          body: "Some issue",
          labels: [double("label", name: "low-priority")],
          html_url: "https://github.com/briancolfer/abcscribe/issues/100")
      end

      it "maps the low-priority label to 'Low'" do
        expect(row["Priority"]).to eq("Low")
      end
    end
  end

  describe ".from_csv_row" do
    let(:csv_row) do
      {
        "GitHub Issue #" => "42",
        "State" => "open",
        "Title" => "Some title",
        "Type" => "Bug",
        "Priority" => "High",
        "Section" => "Profile",
        "Element / Feature" => "Password field",
        "Description" => "Body text",
        "Labels" => "qa-feedback, bug",
        "URL" => "https://github.com/briancolfer/abcscribe/issues/42"
      }
    end

    subject(:row) { described_class.from_csv_row(csv_row) }

    it "returns a hash with the same keys as COLUMNS" do
      expect(row.keys).to eq(QaTools::IssueRow::COLUMNS)
    end

    it "preserves all field values" do
      expect(row["GitHub Issue #"]).to eq("42")
      expect(row["Type"]).to eq("Bug")
      expect(row["Priority"]).to eq("High")
    end

    it "treats a blank GitHub Issue # as a new issue" do
      row_without_number = csv_row.merge("GitHub Issue #" => "")
      expect(described_class.from_csv_row(row_without_number)["GitHub Issue #"]).to eq("")
    end
  end

  describe "#to_csv_row and round-trip" do
    it "survives a full serialise → deserialise round-trip" do
      original = described_class.from_github(gh_issue)
      csv_string = CSV.generate { |csv| csv << original.values }
      parsed_back = CSV.parse(csv_string).first

      column_hash = QaTools::IssueRow::COLUMNS.zip(parsed_back).to_h
      restored = described_class.from_csv_row(column_hash)

      expect(restored["GitHub Issue #"]).to eq("42")
      expect(restored["Title"]).to eq(original["Title"])
      expect(restored["Section"]).to eq("Active Behaviors")
      expect(restored["Priority"]).to eq("High")
    end
  end
end
