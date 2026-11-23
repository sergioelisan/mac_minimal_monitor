import SwiftUI
import ServiceManagement

// MARK: - Store

@MainActor
final class ResourceStore: ObservableObject {
    @Published var memory: MemorySnapshot
    @Published var cpu: CPUSnapshot = .empty
    @Published var lastUpdate: Date = Date()
    @Published var refreshInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            restartTimer()
        }
    }
    @Published var monochromeMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(monochromeMenuBar, forKey: "monochromeMenuBar")
        }
    }

    private let sampler = SystemSampler()
    private var timer: Timer?

    init() {
        let savedInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        self.refreshInterval = savedInterval > 0 ? savedInterval : 2.0
        self.monochromeMenuBar = UserDefaults.standard.bool(forKey: "monochromeMenuBar")
        self.memory = sampler.sampleMemory()

        // Primeira amostra rápida (0.4s) para já exibir a leitura inicial de CPU sem esperar o intervalo completo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.sample()
        }
        restartTimer()
    }

    deinit {
        timer?.invalidate()
    }

    func sample() {
        memory = sampler.sampleMemory()
        cpu = sampler.sampleCPU()
        lastUpdate = Date()
    }

    private func restartTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
        // Permite o sistema agrupar wakeups levemente para economizar bateria
        newTimer.tolerance = min(refreshInterval * 0.15, 0.5)
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    var menuImage: NSImage {
        let ramText = MemorySnapshot.formatCompact(memory.usedBytes)
        let cpuText = "\(Int(cpu.totalUsage.rounded()))%"
        return MenuBarIcon.image(
            ramText: ramText,
            ramPercent: memory.usagePercent,
            cpuText: cpuText,
            cpuPercent: cpu.totalUsage,
            monochrome: monochromeMenuBar
        )
    }
}

// MARK: - Helpers de Cor

private func levelColor(for percent: Double, warn: Double = 70, critical: Double = 90) -> Color {
    if percent >= critical { return .red }
    if percent >= warn { return .orange }
    return .accentColor
}

// MARK: - Subviews

private struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
        }
    }
}

private struct CoreBar: View {
    let index: Int
    let usage: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("Núcleo \(index + 1)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(usage.rounded()))%")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
            }
            ProgressView(value: min(max(usage, 0), 100), total: 100)
                .tint(levelColor(for: usage))
                .scaleEffect(x: 1, y: 0.75, anchor: .center)
        }
    }
}

// MARK: - Popover Principal

struct MenuContent: View {
    @ObservedObject var store: ResourceStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let coreColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cabeçalho
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Monitor de Recursos")
                    .font(.headline)
                Spacer()
                Button {
                    store.sample()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("Atualizar agora")
            }

            Divider()

            // Seção RAM
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Memória RAM")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(MemorySnapshot.formatDetailed(store.memory.usedBytes)) / \(MemorySnapshot.formatDetailed(store.memory.totalBytes))")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                }

                ProgressView(value: store.memory.usagePercent, total: 100)
                    .tint(levelColor(for: store.memory.usagePercent, warn: 75, critical: 90))

                HStack(spacing: 12) {
                    VStack(spacing: 3) {
                        MetricRow(label: "Apps", value: MemorySnapshot.formatDetailed(store.memory.appBytes))
                        MetricRow(label: "Wired", value: MemorySnapshot.formatDetailed(store.memory.wiredBytes))
                        MetricRow(label: "Comprimida", value: MemorySnapshot.formatDetailed(store.memory.compressedBytes))
                    }
                    VStack(spacing: 3) {
                        MetricRow(label: "Cache", value: MemorySnapshot.formatDetailed(store.memory.cachedBytes))
                        MetricRow(label: "Livre", value: MemorySnapshot.formatDetailed(store.memory.freeBytes))
                        MetricRow(label: "Swap", value: MemorySnapshot.formatDetailed(store.memory.swapUsedBytes))
                    }
                }
                .padding(.top, 2)
            }

            Divider()

            // Seção CPU (resumo + núcleos)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("CPU (\(store.cpu.coreCount) núcleos)")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(String(format: "%.1f%%", store.cpu.totalUsage))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                }

                ProgressView(value: store.cpu.totalUsage, total: 100)
                    .tint(levelColor(for: store.cpu.totalUsage))

                HStack {
                    Text(String(
                        format: "Usuário %.1f%% · Sistema %.1f%% · Ocioso %.1f%%",
                        store.cpu.userUsage,
                        store.cpu.systemUsage,
                        store.cpu.idleUsage
                    ))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                if !store.cpu.perCoreUsage.isEmpty {
                    LazyVGrid(columns: coreColumns, spacing: 6) {
                        ForEach(Array(store.cpu.perCoreUsage.enumerated()), id: \.offset) { idx, usage in
                            CoreBar(index: idx, usage: usage)
                        }
                    }
                    .padding(.top, 4)
                }

                HStack {
                    Text("Carga média (1/5/15m)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(
                        format: "%.2f · %.2f · %.2f",
                        store.cpu.loadAverage.0,
                        store.cpu.loadAverage.1,
                        store.cpu.loadAverage.2
                    ))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }

            Divider()

            // Preferências e ações
            HStack {
                Text("Atualização")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $store.refreshInterval) {
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("5s").tag(5.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 115)
                .controlSize(.small)
            }

            Toggle("Ícones monocromáticos na barra", isOn: $store.monochromeMenuBar)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            Toggle(
                "Abrir ao iniciar sessão",
                isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        launchAtLogin = on
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                )
            )
            .toggleStyle(.checkbox)
            .font(.system(size: 11))

            HStack {
                Button("Monitor de Atividade") {
                    let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                }
                .font(.system(size: 11))

                Spacer()

                Button("Sair") {
                    NSApp.terminate(nil)
                }
                .font(.system(size: 11))
                .keyboardShortcut("q")
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 300)
    }
}

// MARK: - App

@main
struct ResourcesMonitorApp: App {
    @StateObject private var store = ResourceStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Image(nsImage: store.menuImage)
        }
        .menuBarExtraStyle(.window)
    }
}
