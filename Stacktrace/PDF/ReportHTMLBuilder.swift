import Foundation

/// Builds the printable HTML for a report covering a date range.
/// Entries are grouped under day headers, clean professional layout.
enum ReportHTMLBuilder {
    static func html(entries: [ReportEntry], from start: Date, to end: Date) -> String {
        let cal = Calendar.current

        // Group by start-of-day, then sort each group by creation order.
        let grouped = Dictionary(grouping: entries) { cal.startOfDay(for: $0.date) }
        let days = grouped.keys.sorted()

        let rangeLabel = "\(DateFormat.short.string(from: start)) – \(DateFormat.short.string(from: end))"

        var body = ""
        if days.isEmpty {
            body = "<p class=\"empty\">No entries logged for this period.</p>"
        } else {
            for day in days {
                let dayEntries = (grouped[day] ?? []).sorted { $0.createdAt < $1.createdAt }
                body += "<section class=\"day\">"
                body += "<h2>\(DateFormat.dayHeader.string(from: day).htmlEscaped)</h2>"
                for entry in dayEntries {
                    body += entryHTML(entry)
                }
                body += "</section>"
            }
        }

        let count = entries.count
        let summary = "\(count) \(count == 1 ? "entry" : "entries") across \(days.count) \(days.count == 1 ? "day" : "days")"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <style>
        \(css)
        </style>
        </head>
        <body>
        <header class="report-head">
          <h1>Work Report</h1>
          <p class="period">\(rangeLabel.htmlEscaped)</p>
          <p class="summary">\(summary.htmlEscaped)</p>
        </header>
        \(body)
        </body>
        </html>
        """
    }

    private static func entryHTML(_ entry: ReportEntry) -> String {
        var parts = "<article class=\"entry\">"
        let title = entry.title.isEmpty ? "Untitled" : entry.title
        parts += "<h3>\(title.htmlEscaped)</h3>"

        if !entry.tags.isEmpty {
            parts += "<div class=\"tags\">"
            for tag in entry.tags {
                parts += "<span class=\"tag\">\(tag.htmlEscaped)</span>"
            }
            parts += "</div>"
        }

        if let mood = entry.mood {
            let labels = ["Rough", "Tough", "Okay", "Good", "Great"]
            let m = max(1, min(5, mood))
            parts += "<p class=\"mood\">How it went: <strong>\(labels[m - 1])</strong> (\(m)/5)</p>"
        }

        if !entry.detail.isEmpty {
            parts += "<p class=\"detail\">\(entry.detail.htmlParagraphs)</p>"
        }
        if !entry.wentWell.isEmpty {
            parts += block(label: "What went well", text: entry.wentWell, cls: "well")
        }
        if !entry.wentBad.isEmpty {
            parts += block(label: "What went bad / to improve", text: entry.wentBad, cls: "bad")
        }
        parts += "</article>"
        return parts
    }

    private static func block(label: String, text: String, cls: String) -> String {
        """
        <div class="note \(cls)">
          <span class="note-label">\(label.htmlEscaped)</span>
          <p>\(text.htmlParagraphs)</p>
        </div>
        """
    }

    private static let css = """
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, "Helvetica Neue", Arial, sans-serif;
      color: #1d1d1f;
      font-size: 12px;
      line-height: 1.5;
      margin: 0;
      padding: 36px 44px;
    }
    .report-head {
      border-bottom: 2px solid #1d1d1f;
      padding-bottom: 10px;
      margin-bottom: 18px;
    }
    .report-head h1 { font-size: 22px; margin: 0 0 4px; }
    .report-head .period { font-size: 13px; font-weight: 600; margin: 0; }
    .report-head .summary { color: #6e6e73; margin: 2px 0 0; }
    .day { margin-bottom: 22px; }
    .day h2 {
      font-size: 14px;
      color: #1d1d1f;
      background: #f2f2f4;
      padding: 6px 10px;
      border-radius: 5px;
      margin: 0 0 10px;
    }
    .entry {
      padding: 0 0 12px 12px;
      margin: 0 0 12px;
      border-left: 3px solid #d2d2d7;
      page-break-inside: avoid;
    }
    .entry h3 { font-size: 13px; margin: 0 0 4px; }
    .tags { margin: 0 0 6px; }
    .tag {
      display: inline-block;
      font-size: 10px;
      font-weight: 600;
      color: #3a3a8c;
      background: #e9e9f7;
      padding: 1px 7px;
      border-radius: 8px;
      margin-right: 4px;
    }
    .detail { margin: 0 0 8px; }
    .mood { margin: 0 0 6px; color: #555; font-size: 11px; }
    .note {
      padding: 6px 10px;
      border-radius: 5px;
      margin: 0 0 6px;
    }
    .note p { margin: 2px 0 0; }
    .note-label { font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: .03em; }
    .note.well { background: #eaf7ee; }
    .note.well .note-label { color: #1e7a36; }
    .note.bad { background: #fdf0e8; }
    .note.bad .note-label { color: #b5530f; }
    .empty { color: #6e6e73; font-style: italic; }
    """
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Escapes, then turns newlines into <br> for readable multi-line notes.
    var htmlParagraphs: String {
        htmlEscaped.replacingOccurrences(of: "\n", with: "<br>")
    }
}
