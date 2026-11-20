// HistoryExportPDF.swift – zweispaltiger Verlaufs-Export (Thai | Latein) als Markdown-Datei oder PDF.
// Das PDF entsteht lokal aus der HTML-Tabelle (HistoryLogic.htmlTable) über den Druckdialog-Mechanismus ohne Dialog,
// mit automatischem Seitenumbruch. Regeln und Tabelle: BilingualExport.swift (getestet in swift-tests).
import AppKit

enum HistoryTableExport {
    static var headers: BilingualHeaders {
        BilingualHeaders(time: R25T.t("col_time"), thai: R25T.t("col_thai"), latin: R25T.t("col_latin"), translit: R25T.t("col_translit"))
    }

    @MainActor
    static func save(_ s: HistorySession, title: String, pdf: Bool) {
        let panel = NSSavePanel()
        panel.title = L.t("hist_export")
        let ext = pdf ? "pdf" : "md"
        panel.allowedContentTypes = [pdf ? .pdf : .plainText]
        panel.nameFieldStringValue = ExportFormats.fileName(base: title, date: s.start, ext: ext)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if pdf {
                try writePDF(html: HistoryLogic.htmlTable(s, title: title, headers: headers), to: url)
            } else {
                let md = HistoryLogic.markdownTable(s, title: title, headers: headers)
                try ExportFormats.fileData(md, csv: false).write(to: url, options: .atomic)
            }
        } catch { NSAlert(error: error).runModal() }
    }

    /// HTML → mehrseitiges A4-PDF. NSAttributedString(html:) braucht den Hauptthread.
    @MainActor
    static func writePDF(html: String, to url: URL) throws {
        guard let data = html.data(using: .utf8),
              let attr = NSAttributedString(html: data, options: [.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
        else { throw CocoaError(.fileWriteUnknown) }
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        tv.textStorage?.setAttributedString(attr)
        tv.isVerticallyResizable = true
        tv.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        tv.sizeToFit()
        let op = NSPrintOperation(view: tv, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run() else { throw CocoaError(.fileWriteUnknown) }
    }
}
