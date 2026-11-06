import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @Query(sort: \DownloadJob.createdAt, order: .reverse) private var jobs: [DownloadJob]
    let engine: DownloadEngine?

    init(engine: DownloadEngine? = nil) {
        self.engine = engine
    }

    var body: some View {
#if os(macOS)
        TabView {
            Tab(.downloads, systemImage: "arrow.down.circle") {
                Form {
                    DownloadSettingsFields(settings: settings, showsSectionHeader: false)
                }
                .formStyle(.grouped)
            }
            Tab(.proxy, systemImage: "network") {
                Form {
                    ProxySettingsFields(settings: settings, showsSectionHeader: false)
                }
                .formStyle(.grouped)
            }
            Tab(.storage, systemImage: "externaldrive") {
                Form {
                    StorageInfoView(jobs: jobs, engine: engine)
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 460)
#else
        NavigationStack {
            Form {
                DownloadSettingsFields(settings: settings)
                ProxySettingsFields(settings: settings)
                StorageInfoView(jobs: jobs, engine: engine)
            }
            .navigationTitle(.settings)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.done) {
                        dismiss()
                    }
                }
            }
        }
#endif
    }
}

private struct DownloadSettingsFields: View {
    let settings: SettingsStore
    let showsSectionHeader: Bool

    init(settings: SettingsStore, showsSectionHeader: Bool = true) {
        self.settings = settings
        self.showsSectionHeader = showsSectionHeader
    }

    var body: some View {
        Section {
            Stepper(value: concurrencyLimitBinding, in: 1...24) {
                LabeledContent(String(localized: .concurrency)) {
                    Text(settings.concurrencyLimit, format: .number)
                }
            }
            Stepper(value: retryLimitBinding, in: 0...10) {
                LabeledContent(String(localized: .retries)) {
                    Text(settings.retryLimit, format: .number)
                }
            }
#if os(macOS)
            TextField(String(localized: .timeoutSecs), value: timeoutSecondsBinding, format: .number.precision(.fractionLength(0)))
#else
            LabeledContent(String(localized: .timeoutSecs)) {
                TextField(String(localized: .timeoutSecs), value: timeoutSecondsBinding, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
#endif
        } header: {
            if showsSectionHeader {
                Text(.downloads)
            }
        }
    }

    private var concurrencyLimitBinding: Binding<Int> {
        Binding {
            settings.concurrencyLimit
        } set: { newValue in
            settings.concurrencyLimit = newValue.clamped(to: 1...24)
        }
    }

    private var retryLimitBinding: Binding<Int> {
        Binding {
            settings.retryLimit
        } set: { newValue in
            settings.retryLimit = newValue.clamped(to: 0...10)
        }
    }

    private var timeoutSecondsBinding: Binding<Double> {
        Binding {
            settings.timeoutSeconds
        } set: { newValue in
            settings.timeoutSeconds = newValue.clamped(to: 5...300)
        }
    }
}

private struct ProxySettingsFields: View {
    @Bindable var settings: SettingsStore
    let showsSectionHeader: Bool

    init(settings: SettingsStore, showsSectionHeader: Bool = true) {
        self.settings = settings
        self.showsSectionHeader = showsSectionHeader
    }

    var body: some View {
        Section {
            Picker(.proxyType, selection: proxyTypeBinding) {
                ForEach(ProxyType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
            Group {
                TextField(String(localized: .host), text: proxyHostBinding)
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
#endif
                TextField(String(localized: .port), value: proxyPortBinding, format: .number.grouping(.never))
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                TextField(String(localized: .username), text: proxyUsernameBinding)
                SecureField(String(localized: .password), text: $settings.proxyPassword)
            }
            .disabled(settings.proxyConfiguration.type == .none)
        } header: {
            if showsSectionHeader {
                Text(.proxy)
            }
        }
    }

    private var proxyTypeBinding: Binding<ProxyType> {
        Binding {
            settings.proxyConfiguration.type
        } set: { newValue in
            var proxy = settings.proxyConfiguration
            proxy.type = newValue
            settings.proxyConfiguration = proxy
        }
    }

    private var proxyHostBinding: Binding<String> {
        Binding {
            settings.proxyConfiguration.host
        } set: { newValue in
            var proxy = settings.proxyConfiguration
            proxy.host = newValue
            settings.proxyConfiguration = proxy
        }
    }

    private var proxyPortBinding: Binding<Int> {
        Binding {
            settings.proxyConfiguration.port
        } set: { newValue in
            var proxy = settings.proxyConfiguration
            proxy.port = newValue.clamped(to: 1...65_535)
            settings.proxyConfiguration = proxy
        }
    }

    private var proxyUsernameBinding: Binding<String> {
        Binding {
            settings.proxyConfiguration.username
        } set: { newValue in
            var proxy = settings.proxyConfiguration
            proxy.username = newValue
            settings.proxyConfiguration = proxy
        }
    }
}

#Preview {
    SettingsView()
        .environment(PreviewSamples.settings)
}
