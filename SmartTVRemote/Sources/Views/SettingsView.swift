import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var connection: TVConnectionManager
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var discovery = DeviceDiscovery()
    @Environment(\.dismiss) private var dismiss

    @State private var pairingTarget: TVDevice?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmForget: TVDevice?

    private var store: DeviceStore { connection.store }

    var body: some View {
        NavigationStack {
            List {
                currentSection
                savedSection
                discoverySection
                preferencesSection
                helpSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() }.fontWeight(.semibold) } }
            .onAppear { discovery.start() }
            .onDisappear { discovery.stop() }
            .sheet(item: $pairingTarget) { device in
                PairingView(device: device).environmentObject(connection)
            }
            .alert("Cambiar nombre", isPresented: $renaming) {
                TextField("Nombre", text: $newName)
                Button("Guardar") {
                    if let id = connection.device?.id, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                        store.update(id) { $0.name = newName.trimmingCharacters(in: .whitespaces) }
                        connection.refreshDevice()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
            .confirmationDialog("¿Olvidar este televisor?", isPresented: Binding(get: { confirmForget != nil }, set: { if !$0 { confirmForget = nil } }), titleVisibility: .visible) {
                Button("Olvidar y borrar emparejamiento", role: .destructive) {
                    if let d = confirmForget { connection.forget(d.id) }
                }
            } message: { Text("Tendrás que volver a emparejarlo para usarlo.") }
        }
    }

    // MARK: Televisor actual

    private var currentSection: some View {
        Section("Televisor actual") {
            if let device = connection.device {
                row("Nombre", device.name)
                row("Dirección IP", device.host)
                HStack {
                    Text("Estado")
                    Spacer()
                    ConnectionDot(state: connection.state)
                    Text(connection.state.label).foregroundStyle(Palette.secondaryText)
                }
                if case .failed(let e) = connection.state {
                    Text([e.errorDescription, e.recoverySuggestion].compactMap { $0 }.joined(separator: " "))
                        .font(.footnote).foregroundStyle(Palette.danger)
                }
                row("Emparejamiento", device.isPaired ? "Emparejado" : "Pendiente")

                Button("Cambiar nombre") { newName = device.name; renaming = true }

                VStack(alignment: .leading, spacing: 4) {
                    Text("MAC para encendido (Wake‑on‑LAN)").font(.footnote).foregroundStyle(Palette.secondaryText)
                    TextField("AA:BB:CC:DD:EE:FF", text: Binding(
                        get: { connection.device?.macAddress ?? "" },
                        set: { v in store.update(device.id) { $0.macAddress = v.isEmpty ? nil : v }; connection.refreshDevice() }
                    ))
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    Text("Opcional. Solo funciona si el televisor admite encendido por red; depende del modelo.")
                        .font(.caption2).foregroundStyle(Palette.secondaryText)
                }

                if connection.state.isConnected || connection.state.isBusy {
                    Button("Desconectar", role: .destructive) { connection.disconnect() }
                } else {
                    Button("Reconectar") { connection.connect(); dismiss() }
                }
                if !device.isPaired || connection.state != .connected {
                    Button("Volver a emparejar") { pairingTarget = device }
                }
                Button("Olvidar televisor", role: .destructive) { confirmForget = device }
            } else {
                Text("Ningún televisor seleccionado.").foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private var savedSection: some View {
        Section("Mis televisores") {
            if store.devices.isEmpty {
                Text("Aún no has guardado ninguno.").foregroundStyle(Palette.secondaryText)
            }
            ForEach(store.devices) { device in
                Button {
                    if device.isPaired { connection.select(device); dismiss() } else { store.upsert(device, select: true); connection.refreshDevice(); pairingTarget = device }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).foregroundStyle(Palette.primaryText)
                            Text(device.host).font(.caption).foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        if device.id == store.selectedID { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent) }
                    }
                }
            }
            .onDelete { offsets in
                let list = store.devices
                offsets.forEach { connection.forget(list[$0].id) }
            }
        }
    }

    private var discoverySection: some View {
        Section {
            HStack {
                Button {
                    discovery.start()
                } label: {
                    Label(discovery.isSearching ? "Buscando…" : "Buscar televisores", systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(discovery.isSearching)
                if discovery.isSearching { Spacer(); ProgressView() }
            }
            if let error = discovery.error {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.errorDescription ?? "").foregroundStyle(Palette.danger)
                    if let hint = error.recoverySuggestion { Text(hint).font(.footnote).foregroundStyle(Palette.secondaryText) }
                    if error == .localNetworkDenied {
                        Button("Abrir Ajustes de iOS") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
            }
            ForEach(discovery.results) { tv in
                Button {
                    let saved = store.device(id: tv.id)
                    var device = saved ?? tv.asDevice
                    device.host = tv.host
                    store.upsert(device, select: true)
                    connection.refreshDevice()
                    if device.isPaired { connection.connect(); dismiss() } else { pairingTarget = store.device(id: tv.id) ?? device }
                } label: {
                    HStack {
                        Image(systemName: "tv").foregroundStyle(Palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.device(id: tv.id)?.name ?? tv.serviceName).foregroundStyle(Palette.primaryText)
                            Text("\(tv.host):\(tv.port)").font(.caption).foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        Text(store.device(id: tv.id)?.isPaired == true ? "Emparejado" : "Emparejar")
                            .font(.caption.bold()).foregroundStyle(Palette.accent)
                    }
                }
            }
            if !discovery.isSearching && discovery.results.isEmpty && discovery.error == nil {
                Text("No se ha encontrado ningún televisor. Revisa la ayuda o añádelo por IP.")
                    .font(.footnote).foregroundStyle(Palette.secondaryText)
            }
            NavigationLink { AddTVManuallyView(onAdded: { device in pairingTarget = device }) } label: {
                Label("Añadir televisor por IP", systemImage: "plus.circle")
            }
        } header: { Text("Buscar televisores") }
    }

    private var preferencesSection: some View {
        Section("Preferencias") {
            Toggle("Vibración háptica", isOn: Binding(get: { settings.hapticsEnabled }, set: { settings.hapticsEnabled = $0 }))
            Toggle("Sonidos de pulsación", isOn: Binding(get: { settings.soundsEnabled }, set: { settings.soundsEnabled = $0 }))
            Toggle("Reconectar automáticamente", isOn: Binding(get: { settings.autoReconnect }, set: { settings.autoReconnect = $0 }))
            Picker("Tema", selection: Binding(get: { settings.theme }, set: { settings.theme = $0 })) {
                ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    private var helpSection: some View {
        Section("Ayuda") {
            NavigationLink("Cómo conectar iPhone y televisor") { HelpView() }
        }
    }

    private var aboutSection: some View {
        Section("Información") {
            row("Versión", Bundle.main.appVersionString)
            NavigationLink("Limitaciones conocidas") { LimitationsView() }
            Text("Sin cuentas, sin anuncios. Todo el tráfico se mantiene en tu red local.")
                .font(.footnote).foregroundStyle(Palette.secondaryText)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(Palette.secondaryText) }
    }
}

extension Bundle {
    var appVersionString: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - Alta manual

struct AddTVManuallyView: View {
    var onAdded: (TVDevice) -> Void
    @EnvironmentObject private var connection: TVConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var ip = ""
    @State private var name = ""
    @State private var checking = false
    @State private var error: TVError?

    var body: some View {
        Form {
            Section {
                TextField("Dirección IP (192.168.1.20)", text: $ip)
                    .keyboardType(.numbersAndPunctuation).autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField("Nombre (opcional)", text: $name)
            } footer: {
                Text("Encuentra la IP en Ajustes ▸ Red del televisor. Se comprobará que responde el servicio de mando remoto (puerto 6466).")
            }
            if let error {
                Section { Text(error.errorDescription ?? "").foregroundStyle(Palette.danger)
                    if let hint = error.recoverySuggestion { Text(hint).font(.footnote) } }
            }
            Section {
                Button {
                    Task { await add() }
                } label: {
                    HStack { Text("Comprobar y añadir"); if checking { Spacer(); ProgressView() } }
                }.disabled(checking || ip.isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Añadir por IP")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add() async {
        error = nil
        let host = ip.trimmingCharacters(in: .whitespaces)
        guard DeviceDiscovery.isValidIPv4(host) else { error = .invalidAddress; return }
        checking = true
        let ok = await DeviceDiscovery.probe(host: host)
        checking = false
        guard ok else { error = .noAndroidTVAtAddress; return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var device = TVDevice(id: "ip:\(host)", name: trimmed.isEmpty ? "Android TV (\(host))" : trimmed, host: host)
        if let existing = connection.store.device(id: device.id) { device = existing }
        connection.store.upsert(device, select: true)
        connection.refreshDevice()
        dismiss()
        if device.isPaired { connection.connect() } else { onAdded(device) }
    }
}

// MARK: - Ayuda

struct HelpView: View {
    var body: some View {
        List {
            Section("Antes de empezar") {
                step("wifi", "Misma red Wi‑Fi", "El iPhone y el televisor deben estar conectados al mismo router (y a la misma red, no a una «red de invitados»).")
                step("tv", "Televisor encendido", "Android TV / Google TV debe estar encendido con la pantalla activa durante el emparejamiento.")
                step("network", "Permiso de Red local", "Al abrir la app por primera vez, acepta «Red local». Si lo rechazaste: Ajustes de iOS ▸ Privacidad y seguridad ▸ Red local ▸ Smart TV Remote.")
            }
            Section("Emparejar") {
                step("1.circle.fill", "Elige tu TV", "En Ajustes ▸ Buscar televisores toca el tuyo (o añádelo por IP).")
                step("2.circle.fill", "Mira la pantalla", "El televisor mostrará un código de 6 caracteres.")
                step("3.circle.fill", "Escríbelo en el iPhone", "Tras emparejar, la app se conectará sola cada vez que la abras.")
            }
            Section("Si no funciona") {
                step("arrow.triangle.2.circlepath", "No aparece el televisor", "Reinicia el router o el televisor, desactiva VPN en el iPhone y comprueba que el router no aísla dispositivos (AP/client isolation).")
                step("power", "Encendido", "Para encender desde la app el televisor debe admitir Wake‑on‑LAN/«Encender con red» y conocer su MAC. Muchos modelos solo se apagan.")
                step("lock.shield", "Emparejamiento rechazado", "Elimina el dispositivo en la app y vuelve a emparejar. Si persiste, reinicia el televisor.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Ayuda")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Palette.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(text).font(.footnote).foregroundStyle(Palette.secondaryText)
            }
        }
        .padding(.vertical, 2)
    }
}

struct LimitationsView: View {
    var body: some View {
        List {
            item("Encendido", "El apagado usa la tecla POWER del protocolo. El encendido solo es posible si el televisor acepta conexiones en reposo o Wake‑on‑LAN.")
            item("Volumen", "El nivel solo se muestra si el televisor lo informa. Con equipos HDMI‑CEC/barra de sonido puede no hacerlo.")
            item("Accesos directos", "El protocolo no lista apps instaladas. La app deduce que una app no está instalada si, tras abrirla, no pasa a primer plano.")
            item("Búsqueda por voz", "El protocolo permite audio, pero esta versión no lo implementa. El botón de lupa abre la búsqueda del televisor; para dictar usa el micrófono del teclado de iOS.")
            item("Ajustes rápidos", "Envía la tecla SETTINGS; algunos fabricantes la ignoran.")
            item("Teclado", "Requiere que haya un campo de texto enfocado en el televisor; no todas las apps exponen su campo al protocolo.")
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Limitaciones")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func item(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.bold())
            Text(text).font(.footnote).foregroundStyle(Palette.secondaryText)
        }
    }
}
