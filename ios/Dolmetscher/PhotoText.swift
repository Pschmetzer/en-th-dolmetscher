// PhotoText.swift – Text aus Foto oder Kamera erkennen (Speisekarte, Schild) und übersetzen. Läuft auf dem Gerät.
import AVFoundation
import PhotosUI
import SwiftUI
import Vision

enum TextScanner {
    /// Erkennt Textzeilen in den Sprachen des Paars (Partnersprache zuerst), von oben nach unten.
    static func lines(in image: UIImage, langs: [Lang] = [.th, .en]) async throws -> [String] {
        guard let cg = image.cgImage else { return [] }
        var req = RecognizeTextRequest()
        req.recognitionLevel = .accurate
        let wanted = langs.map { Locale.Language(identifier: $0.voiceLocale) }
        let supported = req.supportedRecognitionLanguages
        let usable = wanted.filter { w in supported.contains { $0.languageCode == w.languageCode } }
        req.recognitionLanguages = usable.isEmpty ? [Locale.Language(identifier: "en-US")] : usable
        req.usesLanguageCorrection = true
        let obs = try await req.perform(on: cg, orientation: CGImagePropertyOrientation(image.imageOrientation))
        let cells: [Cell] = obs.compactMap { o in
            guard let t = o.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            let b = o.boundingBox
            return Cell(text: t, midY: b.origin.y + b.height / 2, height: b.height, minX: b.origin.x)
        }
        return arrange(cells)
    }

    /// Eine erkannte Textzeile mit Lage im Bild (Vision: y wächst nach oben, 0…1).
    struct Cell: Equatable, Sendable {
        var text: String
        var midY: Double
        var height: Double
        var minX: Double
    }

    /// Zeilenweise von oben nach unten, in der Zeile von links nach rechts. Steht rechts eines Gerichts nur ein Preis
    /// („Pad Thai … 80“), wird beides ein Eintrag; sonst bleiben Spalten getrennte Einträge (nicht vermischt).
    static func arrange(_ cells: [Cell]) -> [String] {
        let top = cells.sorted { $0.midY > $1.midY }
        var rows: [[Cell]] = []
        for c in top {
            if let last = rows.last?.first, abs(last.midY - c.midY) < max(last.height, c.height) * 0.5 {
                rows[rows.count - 1].append(c)
            } else {
                rows.append([c])
            }
        }
        var out: [String] = []
        for row in rows {
            let r = row.sorted { $0.minX < $1.minX }
            var i = 0
            while i < r.count {
                if i + 1 < r.count, !looksLikePrice(r[i].text), looksLikePrice(r[i + 1].text) {
                    out.append(r[i].text + " " + r[i + 1].text); i += 2
                } else {
                    out.append(r[i].text); i += 1
                }
            }
        }
        return out
    }

    /// „80“, „฿120“, „120 บาท“, „12,50 €“: ein Preis ohne Gericht.
    static func looksLikePrice(_ s: String) -> Bool {
        s.range(of: #"^[฿$€£]?\s?\d[\d.,]*\s?(฿|฿|บาท|baht|THB|B|€|\$)?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Kamera über UIImagePickerController (SwiftUI hat keinen eigenen Kamera-Dialog).
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct PhotoTextView: View {
    @Environment(InterpreterModel.self) private var m
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var load: Task<Void, Never>?
    @State private var image: UIImage?
    @State private var lines: [String] = []
    @State private var picked: Set<Int> = []
    @State private var busy = false
    @State private var error: String?
    @State private var camera = false
    @State private var cameraDenied = false
    @State private var scanTask: Task<Void, Never>?

    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// Kamera-Knopf: bei verweigerter Freigabe ein Hinweis mit Weg in die Einstellungen statt einer leeren Ansicht.
    private func openCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: error = T("camera_denied"); cameraDenied = true
        default: cameraDenied = false; camera = true
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        if hasCamera {
                            Button { openCamera() } label: { Label(T("take_photo"), systemImage: "camera") }
                            Spacer()
                        }
                        PhotosPicker(selection: $item, matching: .images) {
                            Label(T("choose_photo"), systemImage: "photo.on.rectangle")
                        }
                    }
                    .buttonStyle(.borderless)
                }
                if let image {
                    Section {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                            .frame(maxWidth: .infinity)
                    }
                }
                if busy {
                    Section {
                        HStack {
                            ProgressView(); Text(T("reading_text"))
                            Spacer()
                            Button(T("cancel")) { scanTask?.cancel(); scanTask = nil; busy = false }.buttonStyle(.borderless)
                        }
                    }
                }
                if let error {
                    Section {
                        Text("⚠️ " + error).foregroundStyle(.red)
                        if cameraDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                            Button(T("open_settings")) { UIApplication.shared.open(url) }
                        }
                    }
                }
                if !lines.isEmpty {
                    Section {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            Button {
                                if picked.contains(i) { picked.remove(i) } else { picked.insert(i) }
                            } label: {
                                HStack {
                                    Image(systemName: picked.contains(i) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(picked.contains(i) ? Color.accentColor : .secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(line)
                                        LineHints(line: line)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: { Text(T("pick_lines")) }
                }
            }
            .navigationTitle(T("photo_text"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(T("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(T("translate")) {
                        let chosen = picked.isEmpty ? lines : picked.sorted().map { lines[$0] }
                        // Jede Zeile einzeln: Speisekarten sind Listen, keine Sätze.
                        for line in chosen.prefix(30) { m.submit(line, speak: false, photo: true) }
                        dismiss()
                    }
                    .disabled(lines.isEmpty)
                }
            }
            .onChange(of: item) { _, new in
                guard let new else { return }
                // 632: ein späteres Foto ersetzt ein früheres; dasselbe Foto lässt sich erneut wählen.
                load?.cancel()
                load = Task {
                    // 582: verkleinert laden statt 12–48 MP in voller Größe.
                    if let data = try? await new.loadTransferable(type: Data.self), !Task.isCancelled,
                       let img = PhotoDownsample.image(from: data) {
                        await scan(img)
                    }
                    if item == new { item = nil }
                }
            }
            .fullScreenCover(isPresented: $camera) {
                CameraPicker { img in Task { await scan(PhotoDownsample.image(img)) } }.ignoresSafeArea()
            }
        }
    }

    /// Erkennung als eigener Task, damit „Abbrechen“ und ein neues Foto die alte Erkennung wirklich verwerfen.
    private func scan(_ img: UIImage) async {
        scanTask?.cancel()
        image = img
        busy = true; error = nil; cameraDenied = false; lines = []; picked = []
        let langs = [m.pair.partner, m.pair.mine]
        let t = Task {
            do {
                let found = try await TextScanner.lines(in: img, langs: langs)
                guard !Task.isCancelled else { return }
                lines = found
                if found.isEmpty { error = T("no_text") }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            if !Task.isCancelled { busy = false }
        }
        scanTask = t
        await t.value
    }
}
