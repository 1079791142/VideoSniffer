#if os(iOS)
import SwiftUI

/// Address bar: back / forward, a URL field that only navigates on return, and
/// reload / stop. Tapping the field selects the whole address so typing
/// replaces it instead of appending.
struct BrowserURLBarView: View {
    let model: BrowserViewModel

    @State private var addressText = ""
    @State private var selection: TextSelection?
    @State private var isShowingInvalidAddress = false
    @FocusState private var isAddressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(.goBack, systemImage: "chevron.backward") {
                    model.goBack()
                }
                .labelStyle(.iconOnly)
                .disabled(!model.canGoBack)

                Button(.goForward, systemImage: "chevron.forward") {
                    model.goForward()
                }
                .labelStyle(.iconOnly)
                .disabled(!model.canGoForward)

                TextField(
                    String(localized: .enterAWebsiteUrl),
                    text: $addressText,
                    selection: $selection
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .submitLabel(.go)
                .focused($isAddressFocused)
                .onSubmit {
                    submitAddress()
                }

                if model.isLoading {
                    Button(.stop, systemImage: "xmark") {
                        model.stopLoading()
                    }
                    .labelStyle(.iconOnly)
                } else {
                    Button(.reload, systemImage: "arrow.clockwise") {
                        model.reload()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(model.currentURL == nil)
                }
            }
            .padding(.horizontal)
            .padding(.vertical)

            ProgressView(value: model.progress)
                .opacity(model.isLoading ? 1 : 0)
        }
        .onAppear {
            syncAddressText()
        }
        .onChange(of: model.currentURL) { _, _ in
            syncAddressText()
        }
        .onChange(of: isAddressFocused) { _, isFocused in
            if isFocused {
                selectAllAddressText()
            } else {
                syncAddressText()
            }
        }
        .alert(String(localized: .enterAValidWebsiteUrl), isPresented: $isShowingInvalidAddress) {
            Button(.ok, role: .cancel) {}
        }
    }

    private func submitAddress() {
        isAddressFocused = false
        guard model.load(addressText) else {
            isShowingInvalidAddress = true
            return
        }
    }

    private func selectAllAddressText() {
        selection = TextSelection(range: addressText.startIndex..<addressText.endIndex)
    }

    /// Keeps the field in step with navigation while the user is not editing.
    private func syncAddressText() {
        guard !isAddressFocused else { return }
        addressText = model.currentURL?.absoluteString ?? ""
    }
}
#endif
