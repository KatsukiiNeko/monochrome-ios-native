// AudioSpecView.swift: the Audio sheet with measured and reported values only.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct AudioSpecView: View {
    let spec: AudioSpec
    let outputMonitor: AudioOutputMonitor
    var equalizer: EQController?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accentColor) private var accent

    private var liveSpec: AudioSpec {
        var copy = spec
        if let output = outputMonitor.output {
            copy.output = output
        }
        return copy
    }

    private var rows: [Row] {
        let spec = liveSpec
        var rows: [Row] = []

        if let codec = spec.codec, !codec.isEmpty {
            let name = AudioCodecName.displayName(for: codec) ?? codec.trimmingCharacters(in: .whitespaces)
            rows.append(Row(
                label: "Format",
                value: name,
                spokenValue: name,
                provenance: spec.provenance(for: .codec)
            ))
        }
        if let container = spec.container, !container.isEmpty {
            rows.append(Row(
                label: "Container",
                value: container.uppercased(),
                spokenValue: container,
                provenance: spec.provenance(for: .container)
            ))
        }
        if let rate = AudioSpecFormat.sampleRate(spec.sampleRateHz) {
            rows.append(Row(
                label: "Sample rate",
                value: rate,
                spokenValue: AudioSpecFormat.spokenSampleRate(spec.sampleRateHz) ?? rate,
                provenance: spec.provenance(for: .sampleRate)
            ))
        }
        if let depth = AudioSpecFormat.bitDepth(spec.bitDepth) {
            rows.append(Row(
                label: "Bit depth",
                value: depth,
                spokenValue: depth,
                provenance: spec.provenance(for: .bitDepth)
            ))
        }
        if let channels = AudioSpecFormat.channels(spec.channels) {
            rows.append(Row(
                label: "Channels",
                value: channels,
                spokenValue: channels,
                provenance: spec.provenance(for: .channels)
            ))
        }
        if let bitrate = AudioSpecFormat.bitrate(
            spec.bitrateKbps,
            estimated: spec.bitrateIsEstimated
        ) {
            rows.append(Row(
                label: "Bitrate",
                value: bitrate,
                spokenValue: bitrate.replacingOccurrences(of: "~", with: ""),
                provenance: spec.provenance(for: .bitrate)
            ))
        }
        if let quality = spec.qualityRequested {
            let qualityValue = AudioSpecFormat.qualityFallback(
                requested: quality,
                actual: spec.qualityActual
            ) ?? quality.spokenName
            rows.append(Row(
                label: "Quality",
                value: qualityValue,
                spokenValue: qualityValue,
                provenance: nil
            ))
        }
        rows.append(Row(
            label: "Source",
            value: spec.source.label,
            spokenValue: spec.source.label,
            provenance: nil
        ))
        if let output = spec.output {
            let rate = AudioSpecFormat.sampleRate(output.sampleRateHz)
            let value = [output.port.label, rate].compactMap { $0 }.joined(separator: " · ")
            rows.append(Row(
                label: "Output",
                value: value,
                spokenValue: value.replacingOccurrences(of: " · ", with: ", "),
                provenance: nil
            ))
        }
        if let equalizer {
            let isOn = equalizer.settings.isEnabled && !equalizer.settings.isFlat
            let value: String
            if isOn, !equalizer.availability.isAvailable {
                value = "On · unavailable"
            } else if isOn {
                value = "On · \(equalizer.selectedPresetName)"
            } else {
                value = "Off"
            }
            rows.append(Row(
                label: "Equalizer",
                value: value,
                spokenValue: value.replacingOccurrences(of: " · ", with: ", "),
                provenance: nil
            ))
        }
        return rows
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            TechnicalLabel(text: row.label)
                            Spacer(minLength: 12)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(row.value)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(Theme.primaryText)
                                    .multilineTextAlignment(.trailing)
                                if let provenance = row.provenance {
                                    Text(provenance.label.uppercased())
                                        .font(Theme.micro)
                                        .tracking(1.0)
                                        .foregroundStyle(Theme.tertiaryText)
                                }
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.label), \(row.spokenValue)")
                    }
                } footer: {
                    Text("Measured values come from the loaded audio. Reported values come from the catalog. Unknown values are left out.")
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listRowBackground(Theme.surface)
            .listRowSeparatorTint(Theme.separator)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .tint(accent)
        }
        .onAppear { outputMonitor.refresh() }
    }

    private struct Row: Identifiable {
        var id: String { label }
        let label: String
        let value: String
        let spokenValue: String
        let provenance: AudioProvenance?
    }
}
#endif
