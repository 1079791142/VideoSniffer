import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct AddDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""
    @State private var outputName = ""
    @State private var authorizedDestinationURL: URL?
    @State private var errorMessage: String?

    let engine: DownloadEngine

    private var destination: AddDownloadDestination {
        AddDownloadDestination(
            urlString: urlString,
            outputName: outputName,
            authorizedURL: authorizedDestinationURL
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .center) {
                        Image(systemName: "arrow.down.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .symbolGradientColorRenderingIfAvailable()
                            .resizable()
                            .frame(width: 48, height: 48)
                            .foregroundStyle(.tint)
                        Text(String(localized: .downloadM3U8Media))
                            .font(.title2)
                            .fontWeight(.medium)
                        Text(String(localized: .addDownloadSupportedLinksDescription))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical)
                    .frame(maxWidth: .infinity)
                }

                Section(String(localized: .m3U8Url)) {
                    HStack {
                        TextField(String(localized: .m3U8Url), text: $urlString)
                            .labelsHidden()
#if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
#endif
                        PasteButton(payloadType: String.self) { strings in
                            guard let pastedURL = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines), !pastedURL.isEmpty else {
                                return
                            }
                            urlString = pastedURL
                            fillOutputNameFromURLIfNeeded(pastedURL)
                        }
                        .labelStyle(.iconOnly)
                    }
                    
                }

                Section(String(localized: .outputFile)) {
                    TextField(String(localized: .outputName), text: $outputName)
#if os(macOS)
                    HStack {
                        LabeledContent(String(localized: .outputPath), value: destination.requestedURL?.path(percentEncoded: false) ?? String(localized: .noOutputPathChosen))
                        Spacer()
                        Button(.choose, systemImage: "square.and.arrow.down") {
                            chooseOutputFile()
                        }
                    }
#endif
                }
            }
            .formStyle(.grouped)
#if os(iOS)
            .navigationTitle(.addDownload)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(.start) {
                        addDownload()
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(
                String(localized: .unableToAddDownload),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button(.ok, role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? String(localized: .unknownError))
            }
        }
    }

#if os(macOS)
    private var panelDirectoryURL: URL? {
        destination.panelDirectoryURL
    }
#endif

    private func fillOutputNameFromURLIfNeeded(_ urlString: String) {
        guard outputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let fileName = URL(string: urlString)?.deletingPathExtension().lastPathComponent,
              !fileName.isEmpty else {
            return
        }

        outputName = fileName
    }

    private func addDownload() {
#if os(macOS)
        if destination.needsAuthorization {
            chooseOutputFile(startsDownloadAfterSelection: true)
            return
        }
#endif
        do {
            let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            try engine.addJob(sourceURLString: trimmedURL, outputName: destination.resolvedName, destinationURL: destination.requestedURL)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

#if os(macOS)
    private func chooseOutputFile(startsDownloadAfterSelection: Bool = false) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = destination.defaultFileName
        panel.directoryURL = panelDirectoryURL
        panel.begin { response in
            guard response == .OK else {
                return
            }
            authorizedDestinationURL = panel.url
            if let selectedName = panel.url?.deletingPathExtension().lastPathComponent,
               !selectedName.isEmpty {
                outputName = selectedName
            }
            if startsDownloadAfterSelection {
                addDownload()
            }
        }
    }
#endif
}

extension Image {
    func symbolGradientColorRenderingIfAvailable() -> Image {
        if #available(iOS 26.0, macOS 26.0, *) {
            symbolColorRenderingMode(.gradient)
        } else {
            self
        }
    }
}

#Preview {
    let container = PreviewSamples.modelContainer()
    let settings = PreviewSamples.settings
    let engine = DownloadEngine(modelContext: container.mainContext, settings: settings)

    AddDownloadView(engine: engine)
        .modelContainer(container)
        .environment(settings)
}
