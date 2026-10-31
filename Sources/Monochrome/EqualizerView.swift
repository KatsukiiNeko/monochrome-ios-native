// EqualizerView.swift: the equalizer sheet, from the preset bar to the effects.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI
import UniformTypeIdentifiers

struct EqualizerView: View {
    let eq: EQController

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accentColor) private var accent

    @State private var selectedBand: Int?
    @State private var isShowingSaveAs = false
    @State private var newPresetName = ""
    @State private var nameError: String?
    @State private var isImporting = false
    @State private var importError: String?
    @State private var pendingDeletion: EQPreset?

    private var sampleRate: Double { eq.sampleRate() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.sectionSpacing) {
                    if let message = eq.availability.message {
                        unavailableBanner(message)
                    }
                    headerSection
                    curveSection
                    modeSection
                    preampSection
                    effectsSection
                    transferSection
                    honestyLine
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Equalizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .tint(accent)
            .onAppear { eq.refreshAvailability() }
            .sheet(isPresented: $isShowingSaveAs) { saveAsSheet }
            .confirmationDialog(
                "Delete “\(pendingDeletion?.name ?? "this preset")”?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let preset = pendingDeletion { eq.deletePreset(id: preset.id) }
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                importError = nil
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        eq.importText(try String(contentsOf: url, encoding: .utf8))
                    } catch {
                        importError = "Could not read that file as UTF-8 text."
                        playerLog.notice("eq import failed: \(error.localizedDescription, privacy: .public)")
                    }
                case .failure(let error):
                    importError = "Could not open that file: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TechnicalSectionHeader(title: "Preset")

                Spacer(minLength: 8)

                Toggle("Equalizer", isOn: Binding(
                    get: { eq.settings.isEnabled },
                    set: { eq.setEnabled($0) }
                ))
                .labelsHidden()
                .tint(accent)
                .accessibilityLabel("Equalizer")
            }

            HStack(spacing: 10) {
                Menu {
                    Section("Monochrome") {
                        ForEach(eq.monochromePresets) { preset in
                            Button(preset.name) { eq.apply(preset) }
                        }
                    }
                    Section("Classic") {
                        ForEach(eq.classicPresets) { preset in
                            Button(preset.name) { eq.apply(preset) }
                        }
                    }
                    if !eq.userPresets.isEmpty {
                        Section("My presets") {
                            ForEach(eq.userPresets) { preset in
                                Button(preset.name) { eq.apply(preset) }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(eq.selectedPresetName)
                            .font(Theme.listRowTitle)
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                        if eq.isPresetModified {
                            Circle()
                                .fill(accent)
                                .frame(width: 5, height: 5)
                                .accessibilityHidden(true)
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .stroke(Theme.border, lineWidth: Theme.hairline)
                    }
                }
                .accessibilityLabel("Preset")
                .accessibilityValue(
                    eq.isPresetModified ? "\(eq.selectedPresetName), modified" : eq.selectedPresetName
                )

                Button {
                    newPresetName = eq.isPresetModified ? "\(eq.selectedPresetName) edit" : eq.selectedPresetName
                    nameError = nil
                    isShowingSaveAs = true
                } label: {
                    Label("Save as", systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: Theme.controlSize, height: Theme.controlSize)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .stroke(Theme.border, lineWidth: Theme.hairline)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save as new preset")

                Button {
                    eq.resetToPreset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: Theme.controlSize, height: Theme.controlSize)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .stroke(Theme.border, lineWidth: Theme.hairline)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset to the selected preset")
            }

            if let preset = eq.selectedPreset, !preset.isBuiltIn {
                Button(role: .destructive) {
                    pendingDeletion = preset
                } label: {
                    Text("Delete “\(preset.name)”")
                        .font(Theme.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.destructive)
            }
        }
    }

    // MARK: - Curve and mode

    private var curveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TechnicalSectionHeader(title: "Response")
            EQCurveView(
                filters: eq.currentFilters,
                sampleRate: sampleRate,
                graphicGains: eq.settings.graphicGains,
                selectedBand: selectedBand
            )
            Text(curveSummary)
                .font(Theme.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The curve is a picture for sighted users; this sentence is the same
    /// information for VoiceOver and for anyone who cannot read the graph.
    private var curveSummary: String {
        let peak = EQResponse.peakDB(filters: eq.currentFilters, sampleRate: sampleRate)
        let preamp = eq.settings.preampDB(sampleRate: sampleRate)
        if eq.currentFilters.isEmpty {
            return "Flat. No band is changing the signal."
        }
        return String(
            format: "Peak %+.1f dB, preamp %+.1f dB. %d active filter%@.",
            peak, preamp, eq.currentFilters.count, eq.currentFilters.count == 1 ? "" : "s"
        )
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: Binding(
                get: { eq.settings.mode },
                set: { eq.setMode($0) }
            )) {
                Text("Graphic").tag(EQMode.graphic)
                Text("Parametric").tag(EQMode.parametric)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Equalizer mode")

            if eq.settings.mode == .graphic {
                graphicBands
            } else {
                parametricBands
            }
        }
    }

    private var graphicBands: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(EQGraphicBands.frequencies.enumerated()), id: \.offset) { index, frequency in
                    EQBandFader(
                        frequency: frequency,
                        gain: index < eq.settings.graphicGains.count ? eq.settings.graphicGains[index] : 0,
                        isSelected: selectedBand == index,
                        onGain: { eq.setGraphicGain($0, at: index) },
                        onSelect: { selectedBand = index }
                    )
                }
            }
            Text("Drag a band to change it. Double tap a band to return it to 0 dB.")
                .font(Theme.caption)
                .foregroundStyle(Theme.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var parametricBands: some View {
        VStack(spacing: 10) {
            ForEach(eq.settings.filters) { filter in
                parametricRow(spec: filter)
            }

            Button {
                eq.addFilter()
            } label: {
                Label("Add band", systemImage: "plus")
                    .font(Theme.listRowTitle)
                    .foregroundStyle(eq.settings.filters.count >= EQSettings.maximumFilters
                        ? Theme.tertiaryText
                        : Theme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: Theme.rowMinHeight)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .stroke(Theme.border, lineWidth: Theme.hairline)
                    }
            }
            .buttonStyle(.plain)
            .disabled(eq.settings.filters.count >= EQSettings.maximumFilters)
            .accessibilityHint(
                eq.settings.filters.count >= EQSettings.maximumFilters
                    ? "The limit of \(EQSettings.maximumFilters) bands is reached"
                    : "Adds a peaking band at 1 kilohertz"
            )
        }
    }

    private func parametricRow(spec: FilterSpec) -> some View {
        let id = spec.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(BiquadKind.allCases, id: \.self) { kind in
                        Button(kindLabel(kind)) {
                            eq.updateFilter(id: id) { $0.kind = kind; $0.q = kind.defaultQ }
                        }
                    }
                } label: {
                    Text(kindLabel(spec.kind))
                        .font(Theme.listRowTitle)
                        .foregroundStyle(Theme.primaryText)
                }
                .accessibilityLabel("Filter type")
                .accessibilityValue(kindLabel(spec.kind))

                Spacer(minLength: 8)

                Text(EQRanges.name(for: spec.frequency))
                    .font(Theme.micro)
                    .tracking(0.8)
                    .foregroundStyle(Theme.tertiaryText)

                Toggle("Enabled", isOn: Binding(
                    get: { spec.enabled },
                    set: { value in eq.updateFilter(id: id) { $0.enabled = value } }
                ))
                .labelsHidden()
                .tint(accent)

                Button(role: .destructive) {
                    eq.removeFilter(id: id)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Theme.destructive)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove band")
            }

            labelledSlider(
                "Frequency",
                value: logFrequency(spec.frequency),
                range: 0...1,
                display: frequencyLabel(spec.frequency),
                spoken: frequencyLabel(spec.frequency)
            ) { fraction in
                eq.updateFilter(id: id) { $0.frequency = expFrequency(fraction) }
            }

            if spec.kind.usesGain {
                labelledSlider(
                    "Gain",
                    value: spec.gainDB,
                    range: FilterSpec.minGainDB...FilterSpec.maxGainDB,
                    display: String(format: "%+.1f dB", spec.gainDB),
                    spoken: String(format: "%+.1f decibels", spec.gainDB)
                ) { value in
                    eq.updateFilter(id: id) { $0.gainDB = (value * 2).rounded() / 2 }
                }
            }

            labelledSlider(
                "Q",
                value: spec.q,
                range: FilterSpec.minQ...FilterSpec.maxQ,
                display: String(format: "%.2f", spec.q),
                spoken: String(format: "%.2f", spec.q)
            ) { value in
                eq.updateFilter(id: id) { $0.q = value }
            }
        }
        .padding(Theme.cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kindLabel(spec.kind)) band at \(frequencyLabel(spec.frequency))")
    }

    // MARK: - Preamp and effects

    private var preampSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TechnicalSectionHeader(title: "Preamp")
                Spacer(minLength: 8)
                if eq.isClipping {
                    TechnicalLabel(text: "Clipping", color: Theme.destructive)
                }
                Toggle("Auto", isOn: Binding(
                    get: { eq.settings.autoPreamp },
                    set: { eq.setPreampAuto($0) }
                ))
                .labelsHidden()
                .tint(accent)
                .accessibilityLabel("Automatic preamp")
            }

            labelledSlider(
                "Preamp",
                value: eq.settings.preampDB(sampleRate: sampleRate),
                range: -24...24,
                display: String(format: "%+.1f dB", eq.settings.preampDB(sampleRate: sampleRate)),
                spoken: String(
                    format: "%+.1f decibels%@",
                    eq.settings.preampDB(sampleRate: sampleRate),
                    eq.settings.autoPreamp ? ", automatic" : ""
                )
            ) { value in
                // Touching the slider takes over from the automatic value.
                eq.setManualPreamp(value)
            }

            Text(eq.settings.autoPreamp
                ? "Headroom is set from the loudest point of the curve. Moving the slider switches to manual."
                : "Manual preamp. Watch the clip light: the curve can exceed 0 dBFS.")
                .font(Theme.caption)
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            TechnicalSectionHeader(title: "Effects")

            effectRow(
                "Bass",
                value: eq.settings.bassDB,
                range: 0...8,
                display: String(format: "%+.1f dB", eq.settings.bassDB)
            ) { eq.setBass($0) } onReset: { eq.setBass(0) }

            effectRow(
                "Clarity",
                value: eq.settings.clarityDB,
                range: 0...6,
                display: String(format: "%+.1f dB", eq.settings.clarityDB)
            ) { eq.setClarity($0) } onReset: { eq.setClarity(0) }

            effectRow(
                "Stereo width",
                value: eq.settings.stereoWidth,
                range: 0...2,
                display: eq.isMono ? "Mono" : String(format: "%.0f%%", eq.settings.stereoWidth * 100)
            ) { eq.setStereoWidth($0) } onReset: { eq.setStereoWidth(1) }
            .disabled(eq.isMono)
            .accessibilityHint(eq.isMono ? "Unavailable for a mono track" : "Widens or narrows the stereo image")

            effectRow(
                "Dynamic Boost",
                value: eq.settings.dynamicBoostDB,
                range: 0...6,
                display: String(format: "%+.1f dB", eq.settings.dynamicBoostDB)
            ) { eq.setDynamicBoost($0) } onReset: { eq.setDynamicBoost(0) }

            Text("Dynamic Boost raises the level into a limiter at −1 dBFS. It cannot make quiet material louder than the limiter allows.")
                .font(Theme.caption)
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func effectRow(
        _ title: String,
        value: Double,
        range: ClosedRange<Double>,
        display: String,
        onChange: @escaping @Sendable (Double) -> Void,
        onReset: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Theme.listRowTitle)
                .foregroundStyle(Theme.primaryText)
                .frame(width: 108, alignment: .leading)
            Slider(value: Binding(get: { value }, set: onChange), in: range)
                .accessibilityLabel(title)
                .accessibilityValue(display)
            Text(display)
                .font(Theme.value)
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
                .frame(width: 62, alignment: .trailing)
            Button {
                onReset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(Theme.caption)
                    .foregroundStyle(value == range.lowerBound ? Theme.tertiaryText : Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset \(title)")
        }
    }

    // MARK: - Import and export

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TechnicalSectionHeader(title: "Import and Export")

            HStack(spacing: 10) {
                Button {
                    isImporting = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(Theme.listRowTitle)
                        .foregroundStyle(Theme.primaryText)
                        .frame(maxWidth: .infinity, minHeight: Theme.rowMinHeight)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .stroke(Theme.border, lineWidth: Theme.hairline)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Reads a parametric equalizer text file you choose")

                ShareLink(item: eq.exportText) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(Theme.listRowTitle)
                        .foregroundStyle(Theme.primaryText)
                        .frame(maxWidth: .infinity, minHeight: Theme.rowMinHeight)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .stroke(Theme.border, lineWidth: Theme.hairline)
                        }
                }
                .accessibilityHint("Shares the current curve as text")
            }

            if let summary = eq.importSummary {
                Text(summary.filters.isEmpty ? "No filters found in that file." : summary.summaryText)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityLabel(
                        summary.filters.isEmpty ? "No filters found in that file" : "Imported \(summary.summaryText)"
                    )
            }

            if let importError {
                Text(importError)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Accept two common text forms: ParametricEQ files and Equalizer APO filters (PK, LS, HS).")
                .font(Theme.caption)
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var honestyLine: some View {
        Text("While the equalizer is on, playback is no longer the unmodified stream: the audio is filtered before it reaches the output.")
            .font(Theme.caption)
            .foregroundStyle(Theme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 8)
    }

    private func unavailableBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(Theme.caption)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
            Text(message)
                .font(Theme.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        }
        .accessibilityElement(children: .combine)
    }

    private var saveAsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Preset name", text: $newPresetName)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Preset name")
                } footer: {
                    if let nameError {
                        Text(nameError).foregroundStyle(Theme.destructive)
                    } else {
                        Text("Saves the current curve as a preset you can edit.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Save Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isShowingSaveAs = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let error = eq.saveAs(name: newPresetName) {
                            nameError = error
                        } else {
                            isShowingSaveAs = false
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .tint(accent)
        }
        .presentationDetents([.height(240)])
    }

    // MARK: - Helpers

    private func labelledSlider(
        _ label: String,
        value: Double,
        range: ClosedRange<Double>,
        display: String,
        spoken: String,
        onChange: @escaping @Sendable (Double) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 68, alignment: .leading)
            Slider(
                value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: onChange),
                in: range
            )
            .accessibilityLabel(label)
            .accessibilityValue(spoken)
            Text(display)
                .font(Theme.value)
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
        }
    }

    private func logFrequency(_ frequency: Double) -> Double {
        let low = log(EQResponse.defaultMinimumFrequency)
        let high = log(EQResponse.defaultMaximumFrequency)
        return min(max((log(max(frequency, 1)) - low) / (high - low), 0), 1)
    }

    private func expFrequency(_ fraction: Double) -> Double {
        let low = log(EQResponse.defaultMinimumFrequency)
        let high = log(EQResponse.defaultMaximumFrequency)
        return exp(low + (high - low) * min(max(fraction, 0), 1))
    }

    private func frequencyLabel(_ frequency: Double) -> String {
        frequency < 1_000
            ? "\(Int(frequency.rounded())) Hz"
            : String(format: "%.1f kHz", frequency / 1_000)
    }

    private func kindLabel(_ kind: BiquadKind) -> String {
        switch kind {
        case .peak: "Peak"
        case .lowShelf: "Low shelf"
        case .highShelf: "High shelf"
        case .highPass: "High pass"
        case .lowPass: "Low pass"
        case .notch: "Notch"
        }
    }
}
#endif
