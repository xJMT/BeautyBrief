import SwiftUI
import AVFoundation

// ─────────────────────────────────────────────
//  ScannerView  —  main camera scanning screen
// ─────────────────────────────────────────────

struct ScannerView: View {

    @StateObject private var vm = ScannerViewModel()
    @EnvironmentObject var allergyVM: AllergyProfileViewModel
    @EnvironmentObject var historyVM: ScanHistoryViewModel

    @State private var cameraPermission: AVAuthorizationStatus = .notDetermined
    @State private var showPermissionAlert = false
    @State private var showProductDetail   = false
    @State private var scanMode: ScanMode  = .barcode
    @State private var triggerCapture      = false

    // Camera warm-up — true once AVCaptureSession.startRunning() completes
    @State private var cameraReady        = false
    @State private var cameraLoadingPulse = false   // drives the loading animation

    // Wait message — shown after 1 s of lookup activity
    @State private var showWaitMessage  = false
    @State private var waitTask: Task<Void, Never>? = nil

    // Enrichment timeout counter — ticks up once per second while in .enriching state
    @State private var enrichSeconds: Int = 0
    @State private var enrichTimer: Task<Void, Never>? = nil

    var body: some View {
        // NavigationStack removed — nav bar was always hidden and nothing
        // is ever pushed onto it; it was the source of the white flash on load.
        ZStack {
            AppTheme.beige.ignoresSafeArea()

            // ── Camera always present when permission granted ─────
            // Pre-warming the AVCaptureSession here means the session is
            // already running by the time the user taps "Start Scanning",
            // eliminating the 0.5–2 s camera boot delay.
            // Barcode callbacks are guarded by `vm.scanState == .scanning`
            // so no spurious scans fire while the idle overlay is visible.
            if cameraPermission == .authorized {
                CameraPreviewView(
                    mode: $scanMode,
                    triggerCapture: $triggerCapture,
                    onBarcodeDetected: { barcode in
                        guard vm.scanState == .scanning, scanMode == .barcode else { return }
                        vm.barcodeDetected(barcode)
                    },
                    onPhotoCaptured: { data in
                        guard let data else { return }
                        vm.photoTaken(data)
                    },
                    onSessionReady: {
                        withAnimation(.easeOut(duration: 0.5)) { cameraReady = true }
                    }
                )
                .ignoresSafeArea()
            }

            switch vm.scanState {
            case .idle:
                idleView
            case .scanning, .lookingUp, .analysingPhoto:
                scanningHUD
            case .needsConfirmation:
                ProductConfirmationView(
                    candidates: vm.candidates,
                    onConfirm: { candidate in
                        vm.confirm(candidate, allergyProfile: allergyVM.profile)
                    },
                    onDismiss: { vm.reset() }
                )
            case .loadingDetails:
                Color.clear
            case .showingResult:
                Color.clear
            case .enriching(let product):
                enrichingView(product)
            case .noIngredients(let product):
                noIngredientsView(product)
            case .error(let msg):
                errorView(msg)
            }

            // ── Camera warm-up loading screen ─────────────────────────
            // Sits above all other layers. Shown from the moment camera
            // permission is confirmed until AVCaptureSession.startRunning()
            // fires the onSessionReady callback (~10 s on first launch).
            if cameraPermission == .authorized && !cameraReady {
                cameraInitializingView
                    .transition(.opacity)
            }
        }
        .onChange(of: vm.scanState) { _, newState in
            if case .showingResult = newState {
                showProductDetail = true
            }
            // Start or cancel the 1-second wait message
            switch newState {
            case .lookingUp, .analysingPhoto, .loadingDetails:
                waitTask?.cancel()
                showWaitMessage = false
                waitTask = Task {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showWaitMessage = true
                        }
                    }
                }
                // Stop enrichment timer if we were enriching
                enrichTimer?.cancel()
                enrichTimer = nil
            case .enriching:
                waitTask?.cancel()
                waitTask = nil
                withAnimation { showWaitMessage = false }
                // Start a per-second counter so the user sees progress
                enrichSeconds = 0
                enrichTimer?.cancel()
                enrichTimer = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled else { return }
                        enrichSeconds += 1
                    }
                }
            default:
                waitTask?.cancel()
                waitTask = nil
                enrichTimer?.cancel()
                enrichTimer = nil
                enrichSeconds = 0
                withAnimation(.easeInOut(duration: 0.3)) {
                    showWaitMessage = false
                }
            }
        }
        .onAppear { checkCameraPermission() }
        .onDisappear {
            waitTask?.cancel()
            waitTask = nil
            enrichTimer?.cancel()
            enrichTimer = nil
        }
        .alert("Camera Access Required",
               isPresented: $showPermissionAlert) {
            Button("Open Settings") { openSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("BeautyBrief needs camera access to scan beauty products.")
        }
        .sheet(isPresented: $showProductDetail, onDismiss: {
            if let product = vm.confirmedProduct,
               let analysis = vm.analysisResult {
                let result = ScanResult(
                    product: product,
                    allergyMatches: analysis.allergyMatches.map { AllergyMatchRecord(from: $0) },
                    expiryWarning: vm.batchResult?.isExpired ?? false || vm.batchResult?.isNearExpiry ?? false,
                    confidenceScore: vm.candidates.first?.confidenceScore ?? 1.0,
                    identificationMethod: vm.candidates.first?.identificationMethod.rawValue ?? "Barcode"
                )
                historyVM.addScan(result)
            }
            vm.reset()
        }) {
            if let product = vm.confirmedProduct {
                ProductDetailView(
                    product: product,
                    analysisResult: vm.analysisResult,
                    batchResult: vm.batchResult,
                    confidenceScore: vm.candidates.first?.confidenceScore ?? 1.0
                )
            }
        }
    }

    // MARK: — Camera Initialising Overlay

    private var cameraInitializingView: some View {
        ZStack {
            // ── Gradient background ─────────────────────────────────
            LinearGradient(
                colors: [
                    AppTheme.beige,
                    AppTheme.pinkLight.opacity(0.35),
                    AppTheme.beige,
                    AppTheme.beigeMid.opacity(0.50)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Wordmark ────────────────────────────────────────
                BeautyBriefWordmark(size: 30)
                    .padding(.top, 72)

                Spacer()

                // ── Pulsing camera icon ──────────────────────────────
                ZStack {
                    // Outer soft halo
                    Circle()
                        .fill(AppTheme.pink.opacity(0.18))
                        .frame(width: 140, height: 140)
                        .scaleEffect(cameraLoadingPulse ? 1.14 : 0.90)
                        .animation(
                            .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                            value: cameraLoadingPulse
                        )
                    // Inner blush disc
                    Circle()
                        .fill(AppTheme.pinkLight)
                        .frame(width: 96, height: 96)
                        .scaleEffect(cameraLoadingPulse ? 1.06 : 0.96)
                        .animation(
                            .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                            value: cameraLoadingPulse
                        )
                    // Camera icon
                    Image(systemName: "camera.fill")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(AppTheme.pinkDark)
                }

                // ── Copy ─────────────────────────────────────────────
                VStack(spacing: 8) {
                    Text("Preparing camera…")
                        .font(AppTheme.serif(20, weight: .semibold))
                        .foregroundStyle(AppTheme.mochaDark)
                    Text("Just a moment while we get ready")
                        .font(AppTheme.sans(14))
                        .foregroundStyle(AppTheme.textSoft)
                }
                .padding(.top, 28)

                // ── Spinner ───────────────────────────────────────────
                ProgressView()
                    .tint(AppTheme.pinkDark)
                    .scaleEffect(1.1)
                    .padding(.top, 20)

                Spacer()
            }
        }
        .onAppear { cameraLoadingPulse = true }
    }

    // MARK: — Idle State

    private var idleView: some View {
        GeometryReader { geo in
            ZStack {
                // ── Multi-layer gradient background ──────────────────
                LinearGradient(
                    colors: [
                        AppTheme.beige,
                        AppTheme.pinkLight.opacity(0.40),
                        AppTheme.beige,
                        AppTheme.beigeMid.opacity(0.60)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // ── Decorative blurred circle accents ────────────────
                Circle()
                    .fill(AppTheme.pink.opacity(0.18))
                    .frame(width: geo.size.width * 0.7)
                    .blur(radius: 60)
                    .offset(x: geo.size.width * 0.25, y: -geo.size.height * 0.28)

                Circle()
                    .fill(AppTheme.mocha.opacity(0.06))
                    .frame(width: geo.size.width * 0.55)
                    .blur(radius: 50)
                    .offset(x: -geo.size.width * 0.30, y: geo.size.height * 0.30)

                VStack(spacing: 0) {

                    // ── Wordmark ─────────────────────────────────────
                    BeautyBriefWordmark(size: 38)
                        .padding(.top, geo.safeAreaInsets.top + 52)

                    Spacer()

                    // ── Hero camera button ───────────────────────────
                    ScanHeroButton {
                        withAnimation(.easeInOut(duration: 0.2)) { vm.startScanning() }
                    }
                    .frame(width: geo.size.width * 0.72,
                           height: geo.size.width * 0.72)

                    Spacer().frame(height: geo.size.height * 0.044)

                    // ── Tagline + feature highlights ─────────────────
                    VStack(spacing: 20) {
                        VStack(spacing: 2) {
                            Text("Tap above to scan your beauty product")
                                .font(AppTheme.serif(17, weight: .semibold))
                                .foregroundStyle(AppTheme.mochaDark)
                            Text("TO SEE:")
                                .font(AppTheme.serif(14, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                        .multilineTextAlignment(.center)

                        VStack(spacing: 10) {
                            ScanFeatureRow(icon: "list.bullet.clipboard",
                                           title: "Full Ingredient Breakdown",
                                           subtitle: "Every INCI ingredient decoded & explained")
                            ScanFeatureRow(icon: "exclamationmark.shield.fill",
                                           title: "Allergen & Safety Check",
                                           subtitle: "Matched against your personal allergy profile")
                            ScanFeatureRow(icon: "calendar.badge.clock",
                                           title: "Expiry & Batch Decode",
                                           subtitle: "Manufacturing date + period after opening")
                            ScanFeatureRow(icon: "sparkles",
                                           title: "Similar Products",
                                           subtitle: "Safer alternatives ranked by ingredient match")
                        }
                        .padding(.horizontal, 28)
                    }

                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: — Scanning HUD (overlays the always-on camera layer)

    private var scanningHUD: some View {
        ZStack {
            // Dark scrim at top and bottom
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.55), Color.clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 160)
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 200)
            }
            .ignoresSafeArea()

            VStack {
                // ── Top bar — wordmark only ──────────────────────────
                HStack(spacing: 0) {
                    BeautyBriefWordmark(size: 44, lightMode: true)
                    Text(".")
                        .font(AppTheme.serif(44, weight: .light))
                        .foregroundStyle(AppTheme.pinkLight)
                }
                .padding(.top, 16)

                // ── Mode picker + exit button ────────────────────────
                HStack(spacing: 10) {
                    Picker("", selection: $scanMode) {
                        Label("Barcode", systemImage: "barcode.viewfinder").tag(ScanMode.barcode)
                        Label("Photo AI", systemImage: "camera.fill").tag(ScanMode.photo)
                    }
                    .pickerStyle(.segmented)
                    .colorMultiply(.white)

                    Button { vm.reset() } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Spacer()

                // ── Scan frame ───────────────────────────────────────
                ScanningFrame(isLoading: vm.scanState.isLoading)
                    .frame(
                        width:  scanMode == .barcode ? 280 : 260,
                        height: scanMode == .barcode ? 160 : 320
                    )
                    .animation(.easeInOut(duration: 0.25), value: scanMode)

                Spacer()

                // ── Wait message (appears after 1 s of lookup) ───────
                if showWaitMessage && vm.scanState.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(AppTheme.pinkDark)
                            .scaleEffect(0.85)
                        Text("One moment…")
                            .font(AppTheme.serif(15, weight: .semibold))
                            .foregroundStyle(AppTheme.mochaDark)
                        Text("Fetching ingredient data")
                            .font(AppTheme.sans(13))
                            .foregroundStyle(AppTheme.textSoft)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 13)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // ── Bottom controls ──────────────────────────────────
                VStack(spacing: 16) {
                    if vm.scanState.isLoading {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text(vm.scanState.statusMessage)
                                .font(AppTheme.sans(14))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.30))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    } else if scanMode == .photo {
                        VStack(spacing: 14) {
                            BeautyCameraButton(isLoading: vm.scanState.isLoading) {
                                triggerCapture = true
                            }
                            Text("Point at the product label and tap")
                                .font(AppTheme.sans(13))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "barcode.viewfinder")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("Point at barcode — scans automatically")
                                .font(AppTheme.sans(13))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.28))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }

                    if let error = vm.errorMessage {
                        VStack(spacing: 10) {
                            Text(error)
                                .font(AppTheme.sans(13))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Button {
                                vm.startScanning()
                            } label: {
                                Text("Try Again")
                                    .font(AppTheme.sans(14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.mocha)
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                            }
                        }
                    }
                }
                .padding(.bottom, 52)
            }
        }
    }

    // MARK: — Error

    private func errorView(_ message: String) -> some View {
        ZStack {
            AppTheme.beige.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(AppTheme.warning.opacity(0.12))
                        .frame(width: 90, height: 90)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(AppTheme.warning)
                }
                VStack(spacing: 8) {
                    Text("Something went wrong")
                        .font(AppTheme.serif(20, weight: .semibold))
                        .foregroundStyle(AppTheme.mochaDark)
                    Text(message)
                        .font(AppTheme.sans(14))
                        .foregroundStyle(AppTheme.textSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                Button("Try Again") { vm.reset() }
                    .font(AppTheme.sans(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 13)
                    .background(AppTheme.mocha)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
                Spacer()
            }
            .padding()
        }
    }

    // MARK: — No Ingredients Found

    // MARK: — Enriching View (searching online for ingredients)
    private func enrichingView(_ product: Product) -> some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.beige, AppTheme.pinkLight.opacity(0.25), AppTheme.beige],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 36) {

                // Animated icon
                ZStack {
                    Circle()
                        .fill(AppTheme.pinkLight)
                        .frame(width: 96, height: 96)
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(AppTheme.pinkDark)
                }

                // Copy
                VStack(spacing: 10) {
                    Text("Found it!")
                        .font(AppTheme.serif(22, weight: .semibold))
                        .foregroundStyle(AppTheme.mochaDark)

                    Text(product.knownBrand.map { "\($0) \(product.name)" } ?? product.name)
                        .font(AppTheme.serif(15, weight: .semibold))
                        .foregroundStyle(AppTheme.mocha)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    // Live elapsed counter — shows "Still searching…" after 5 s
                    Group {
                        if enrichSeconds >= 5 {
                            Text("Still searching… (\(enrichSeconds)s)")
                                .foregroundStyle(AppTheme.warning.opacity(0.8))
                        } else {
                            Text("Searching for ingredients online…")
                                .foregroundStyle(AppTheme.textSoft)
                        }
                    }
                    .font(AppTheme.sans(14))
                    .animation(.easeInOut(duration: 0.3), value: enrichSeconds)
                    .padding(.top, 2)
                }

                // Spinner + source labels
                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppTheme.pinkDark)
                        .scaleEffect(1.2)

                    // LazyVGrid wraps chips onto new rows on narrow screens (e.g. iPhone SE)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 90, maximum: 160), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(["Open Beauty Facts", "INCIDecoder", "Brand Site"], id: \.self) { source in
                            Text(source)
                                .font(AppTheme.sans(11))
                                .foregroundStyle(AppTheme.textSoft.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.beigeMid.opacity(0.6))
                                .clipShape(Capsule())
                        }
                    }
                }

                // Cancel
                Button {
                    vm.reset()
                } label: {
                    Text("Cancel")
                        .font(AppTheme.sans(14))
                        .foregroundStyle(AppTheme.textSoft)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
        }
    }

    private func noIngredientsView(_ product: Product) -> some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.beige, AppTheme.pinkLight.opacity(0.30), AppTheme.beige],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button { vm.reset() } label: {
                        ZStack {
                            Circle()
                                .fill(AppTheme.beigeMid)
                                .frame(width: 36, height: 36)
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.mocha)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                Spacer()

                VStack(spacing: 28) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(AppTheme.pinkLight)
                            .frame(width: 96, height: 96)
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(AppTheme.pinkDark)
                    }

                    // Message
                    VStack(spacing: 10) {
                        Text("We're sorry!")
                            .font(AppTheme.serif(24, weight: .semibold))
                            .foregroundStyle(AppTheme.mochaDark)

                        Text("We weren't able to obtain the ingredient list for")
                            .font(AppTheme.sans(15))
                            .foregroundStyle(AppTheme.textSoft)
                            .multilineTextAlignment(.center)

                        Text(product.knownBrand.map { "\($0) \(product.name)" } ?? product.name)
                            .font(AppTheme.serif(16, weight: .semibold))
                            .foregroundStyle(AppTheme.mocha)
                            .multilineTextAlignment(.center)

                        Text("at this time. Our team is constantly expanding the database — please check back soon.")
                            .font(AppTheme.sans(14))
                            .foregroundStyle(AppTheme.textSoft)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 36)

                    // What you can do card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("In the meantime, you can:")
                            .font(AppTheme.sans(13, weight: .semibold))
                            .foregroundStyle(AppTheme.mochaDark)

                        VStack(alignment: .leading, spacing: 10) {
                            NoIngredientsTip(icon: "camera.fill",
                                             text: "Try Photo mode — AI may identify a different version")
                            NoIngredientsTip(icon: "barcode.viewfinder",
                                             text: "Scan a different barcode on the packaging")
                            // Report tip — confirmation shown because report is auto-sent
                            VStack(spacing: 6) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "exclamationmark.bubble")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AppTheme.pinkDark)
                                        .frame(width: 18)
                                        .padding(.top, 1)
                                    Text("Report the missing product so we can add it")
                                        .font(AppTheme.sans(13))
                                        .foregroundStyle(AppTheme.textMain)
                                }
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Color(red: 0.22, green: 0.62, blue: 0.42))
                                    Text("Your request has been sent.")
                                        .font(AppTheme.sans(15, weight: .bold))
                                        .foregroundStyle(Color(red: 0.22, green: 0.62, blue: 0.42))
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {

                        RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.beigeDark.opacity(0.4), lineWidth: 1)
                    }
                    .padding(.horizontal, 28)
                }

                Spacer()

                // Scan again CTA
                Button {
                    vm.reset()
                    vm.startScanning()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Scan Another Product")
                            .font(AppTheme.sans(16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.mocha)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 44)
            }
        }
    }

    // MARK: — Permissions

    private func checkCameraPermission() {
        cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraPermission {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermission = granted ? .authorized : .denied
                    if !granted { showPermissionAlert = true }
                }
            }
        case .denied, .restricted:
            showPermissionAlert = true
        default: break
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}

// MARK: — BeautyBrief Wordmark

struct BeautyBriefWordmark: View {
    var size: CGFloat = 17
    var lightMode: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Text("Beauty")
                .font(AppTheme.serif(size, weight: .bold))
                .foregroundStyle(lightMode ? .white : AppTheme.mochaDark)
            Text("Brief")
                .font(AppTheme.serif(size, weight: .regular))
                .foregroundStyle(lightMode ? AppTheme.pinkLight : Color(red: 0.98, green: 0.82, blue: 0.90))
        }
        .tracking(0.3)
    }
}

// MARK: — Hero Scan Button (idle screen)

struct ScanHeroButton: View {
    let action: () -> Void

    @State private var breathe   = false
    @State private var arcA      = 0.0   // outermost — 34 s clockwise
    @State private var arcB      = 0.0   // 24 s counter-clockwise
    @State private var arcC      = 0.0   // 42 s clockwise  (widest arc)
    @State private var arcD      = 0.0   // 20 s counter-clockwise
    @State private var arcE      = 0.0   // innermost — 30 s clockwise
    @State private var bokeh     = 0.0   // floating dots — 50 s clockwise
    @State private var starSpin  = 0.0   // each star self-rotates — 7 s CW

    // ── Rose gold editorial palette ───────────────────────────────────
    private let roseGold  = Color(red: 0.88, green: 0.62, blue: 0.52)
    private let deepRose  = Color(red: 0.72, green: 0.34, blue: 0.44)
    private let blush     = Color(red: 0.97, green: 0.84, blue: 0.88)
    private let champagne = Color(red: 1.00, green: 0.95, blue: 0.84)
    private let gold      = Color(red: 0.92, green: 0.76, blue: 0.50)

    // ── 29 stars — (initial angle °, orbit-radius factor, size factor, speed group, color index)
    // Speed groups share the existing arc animation states:
    //   0 = arcA  (34 s CW)   1 = -arcB (24 s CCW)  2 = arcC  (42 s CW)
    //   3 = -arcD (20 s CCW)  4 = arcE  (30 s CW)   5 = bokeh (50 s CW)
    // Color indices: 0=roseGold  1=deepRose  2=blush  3=champagne  4=gold
    private let starData: [(offset: Double, r: CGFloat, sz: CGFloat, group: Int, colorIdx: Int)] = [
        // group 0 – arcA 34 s CW
        (  12, 0.44, 0.030, 0, 0), ( 105, 0.36, 0.024, 0, 2), ( 197, 0.41, 0.028, 0, 4),
        ( 280, 0.38, 0.022, 0, 1), ( 340, 0.45, 0.026, 0, 3),
        // group 1 – arcB 24 s CCW
        (  48, 0.33, 0.025, 1, 2), ( 130, 0.46, 0.030, 1, 0), ( 210, 0.30, 0.022, 1, 4),
        ( 295, 0.43, 0.027, 1, 3), (  78, 0.40, 0.023, 1, 1),
        // group 2 – arcC 42 s CW
        (  22, 0.26, 0.028, 2, 3), ( 115, 0.42, 0.024, 2, 0), ( 190, 0.35, 0.030, 2, 2),
        ( 265, 0.28, 0.022, 2, 4), ( 330, 0.44, 0.026, 2, 1),
        // group 3 – arcD 20 s CCW
        (  60, 0.37, 0.023, 3, 4), ( 145, 0.32, 0.028, 3, 0), ( 230, 0.45, 0.025, 3, 2),
        ( 310, 0.34, 0.022, 3, 3),
        // group 4 – arcE 30 s CW
        (  90, 0.20, 0.024, 4, 1), ( 175, 0.38, 0.030, 4, 3), ( 250, 0.22, 0.022, 4, 0),
        ( 320, 0.41, 0.027, 4, 2),
        // group 5 – bokeh 50 s CW
        (  35, 0.43, 0.026, 5, 0), ( 155, 0.27, 0.024, 5, 4), ( 240, 0.46, 0.030, 5, 2),
        ( 300, 0.31, 0.022, 5, 1), (  70, 0.39, 0.025, 5, 3), ( 215, 0.24, 0.023, 5, 0),
    ]

    var body: some View {
        Button(action: action) {
            GeometryReader { geo in
                let S  = min(geo.size.width, geo.size.height)
                let cx = geo.size.width  / 2
                let cy = geo.size.height / 2

                ZStack {

                    // ── 1. Ambient rose gold pulse ─────────────────────
                    Circle()
                        .fill(RadialGradient(
                            colors: [roseGold.opacity(0.22),
                                     blush.opacity(0.10),
                                     Color.clear],
                            center: .center,
                            startRadius: S * 0.08,
                            endRadius:   S * 0.50))
                        .frame(width: S, height: S)
                        .scaleEffect(breathe ? 1.10 : 0.92)
                        .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true),
                                   value: breathe)
                        .position(x: cx, y: cy)

                    // ── 2. Arc A — outermost, 58%, 5.5 pt, 34 s CW ────
                    Circle()
                        .trim(from: 0, to: 0.58)
                        .stroke(
                            AngularGradient(
                                colors: [Color.clear,
                                         roseGold.opacity(0.55),
                                         deepRose.opacity(0.90),
                                         roseGold.opacity(0.65),
                                         blush.opacity(0.35),
                                         Color.clear],
                                center: .center),
                            style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                        .frame(width: S * 0.90, height: S * 0.90)
                        .rotationEffect(.degrees(arcA))
                        .position(x: cx, y: cy)
                        .blendMode(.plusLighter)

                    // ── 3. Arc B — 40%, 3.5 pt, 24 s CCW ─────────────
                    Circle()
                        .trim(from: 0, to: 0.40)
                        .stroke(
                            AngularGradient(
                                colors: [Color.clear,
                                         deepRose.opacity(0.50),
                                         roseGold.opacity(0.88),
                                         gold.opacity(0.60),
                                         Color.clear],
                                center: .center),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .frame(width: S * 0.76, height: S * 0.76)
                        .rotationEffect(.degrees(-arcB))
                        .position(x: cx, y: cy)
                        .blendMode(.plusLighter)

                    // ── 4. Arc C — 70%, 7 pt, 42 s CW (thickest) ─────
                    Circle()
                        .trim(from: 0, to: 0.70)
                        .stroke(
                            AngularGradient(
                                colors: [Color.clear,
                                         blush.opacity(0.40),
                                         champagne.opacity(0.72),
                                         roseGold.opacity(0.82),
                                         blush.opacity(0.45),
                                         Color.clear],
                                center: .center),
                            style: StrokeStyle(lineWidth: 7.0, lineCap: .round))
                        .frame(width: S * 0.62, height: S * 0.62)
                        .rotationEffect(.degrees(arcC))
                        .position(x: cx, y: cy)
                        .blendMode(.plusLighter)

                    // ── 5. Arc D — 36%, 3 pt, 20 s CCW ───────────────
                    Circle()
                        .trim(from: 0, to: 0.36)
                        .stroke(
                            AngularGradient(
                                colors: [Color.clear,
                                         gold.opacity(0.55),
                                         champagne.opacity(0.85),
                                         gold.opacity(0.50),
                                         Color.clear],
                                center: .center),
                            style: StrokeStyle(lineWidth: 3.0, lineCap: .round))
                        .frame(width: S * 0.50, height: S * 0.50)
                        .rotationEffect(.degrees(-arcD))
                        .position(x: cx, y: cy)
                        .blendMode(.plusLighter)

                    // ── 6. Arc E — innermost, 52%, 4.5 pt, 30 s CW ───
                    Circle()
                        .trim(from: 0, to: 0.52)
                        .stroke(
                            AngularGradient(
                                colors: [Color.clear,
                                         roseGold.opacity(0.45),
                                         deepRose.opacity(0.78),
                                         blush.opacity(0.58),
                                         Color.clear],
                                center: .center),
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .frame(width: S * 0.38, height: S * 0.38)
                        .rotationEffect(.degrees(arcE))
                        .position(x: cx, y: cy)
                        .blendMode(.plusLighter)

                    // ── 7. Rose gold bokeh dots ────────────────────────
                    ForEach(0..<8, id: \.self) { i in
                        let base  = Double(i) * (360.0 / 8.0)
                        let angle = base + bokeh
                        let rad   = angle * .pi / 180
                        let r     = S * (i % 2 == 0 ? 0.43 : 0.39)
                        let dotSz = S * (i % 3 == 0 ? 0.020 : 0.014)
                        let col: Color = i % 3 == 0 ? roseGold.opacity(0.75)
                                       : i % 3 == 1 ? gold.opacity(0.60)
                                                     : blush.opacity(0.55)
                        Circle()
                            .fill(col)
                            .frame(width: dotSz, height: dotSz)
                            .blur(radius: 1.2)
                            .offset(x: r * CGFloat(sin(rad)),
                                    y: -r * CGFloat(cos(rad)))
                            .position(x: cx, y: cy)
                    }

                    // ── 8. 29 five-pointed stars — true GPU orbital motion
                    // Each star sits at offset (0, -r) inside a full-size
                    // container, then rotationEffect spins that container
                    // around the button centre — smooth, frame-by-frame orbit.
                    let starColors: [Color] = [roseGold, deepRose, blush, champagne, gold]
                    ForEach(0..<29, id: \.self) { i in
                        let s   = starData[i]
                        let r   = S * s.r
                        let sz  = S * s.sz
                        let col = starColors[s.colorIdx]
                        ZStack {
                            FivePointedStar()
                                .fill(col.opacity(0.82))
                                .frame(width: sz, height: sz)
                                .rotationEffect(.degrees(starSpin))  // self-spin
                                .offset(x: 0, y: -r)                // orbit arm
                        }
                        .frame(width: S, height: S)
                        .rotationEffect(.degrees(orbitAngle(for: s)))
                        .position(x: cx, y: cy)
                        .blendMode(.plusLighter)
                    }

                    // ── 9. Camera icon — editorial rose gold ───────────
                    Image(systemName: "camera.fill")
                        .font(.system(size: S * 0.21, weight: .regular))
                        .foregroundStyle(Color(red: 0.98, green: 0.82, blue: 0.90))
                        .position(x: cx, y: cy)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .buttonStyle(HeroCameraButtonStyle())
        .onAppear {
            breathe = true
            withAnimation(.linear(duration: 34).repeatForever(autoreverses: false)) { arcA = 360 }
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) { arcB = 360 }
            withAnimation(.linear(duration: 42).repeatForever(autoreverses: false)) { arcC = 360 }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) { arcD = 360 }
            withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) { arcE = 360 }
            withAnimation(.linear(duration: 50).repeatForever(autoreverses: false)) { bokeh    = 360 }
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false))  { starSpin = 360 }
        }
        .accessibilityLabel("Scan product")
    }

    // MARK: — Orbit angle helper
    // Returns the current orbital rotation (degrees) for a given star.
    // SwiftUI animates @State vars through its render layer so rotationEffect
    // receives live interpolated values every frame — true smooth orbit.
    private func orbitAngle(for s: (offset: Double, r: CGFloat, sz: CGFloat, group: Int, colorIdx: Int)) -> Double {
        switch s.group {
        case 0:  return  arcA + s.offset   // 34 s CW
        case 1:  return -arcB + s.offset   // 24 s CCW
        case 2:  return  arcC + s.offset   // 42 s CW
        case 3:  return -arcD + s.offset   // 20 s CCW
        case 4:  return  arcE + s.offset   // 30 s CW
        default: return  bokeh + s.offset  // 50 s CW
        }
    }
}

// MARK: — Scan Feature Row

struct ScanFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.pinkLight)
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.pinkDark)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.sans(13, weight: .semibold))
                    .foregroundStyle(AppTheme.mochaDark)
                Text(subtitle)
                    .font(AppTheme.sans(11))
                    .foregroundStyle(AppTheme.textSoft)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {

            RoundedRectangle(cornerRadius: 14)
            .stroke(AppTheme.beigeDark.opacity(0.4), lineWidth: 1)
        }
    }
}

// MARK: — Hero camera button press style

struct HeroCameraButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: — Five-Pointed Star Shape

struct FivePointedStar: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let outerR = min(rect.width, rect.height) / 2.0
        let innerR = outerR * 0.382   // classic golden-ratio inner radius
        var path = Path()
        for i in 0..<10 {
            // Points alternate outer / inner, starting at top (-90°)
            let angleDeg = Double(i) * 36.0 - 90.0
            let angleRad = angleDeg * .pi / 180.0
            let r = i % 2 == 0 ? outerR : innerR
            let x = cx + CGFloat(cos(angleRad)) * r
            let y = cy + CGFloat(sin(angleRad)) * r
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else       { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: — Scanning frame animation

struct ScanningFrame: View {
    let isLoading: Bool
    @State private var scanLine: CGFloat = 0
    @State private var animated = false

    var body: some View {
        ZStack {
            // Corner brackets
            ForEach(0..<4) { i in
                CornerBracket(index: i)
                    .stroke(isLoading ? AppTheme.pink : Color.white, lineWidth: 2.5)
            }
            // Animated scan line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, AppTheme.pinkDark.opacity(0.85), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .offset(y: scanLine)
                .animation(
                    .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                    value: animated
                )
        }
        .onAppear {
            scanLine = -60
            animated = true
            withAnimation { scanLine = 60 }
        }
    }
}

struct CornerBracket: Shape {
    let index: Int  // 0=TL, 1=TR, 2=BL, 3=BR
    let size: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch index {
        case 0:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + size))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + size, y: rect.minY))
        case 1:
            path.move(to: CGPoint(x: rect.maxX - size, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + size))
        case 2:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY - size))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + size, y: rect.maxY))
        case 3:
            path.move(to: CGPoint(x: rect.maxX - size, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - size))
        default: break
        }
        return path
    }
}

// MARK: — BeautyCameraButton
// A layered, premium shutter button inspired by a luxury skincare compact.
// Uses only native SwiftUI + SF Symbols. No third-party packages.
//
// Visual layers (inside out):
//   1. Outer frosted ring     — .ultraThinMaterial, beautiful over live camera
//   2. Blush-pink accent ring — soft gradient stroke, 1.5 pt
//   3. Pearl inner disc       — radial gradient cream→beige with dimensional shadow
//   4. Shimmer arc highlight  — slow 8-second rotation, white fade
//   5. Center icon / spinner  — camera.macro in mocha gradient; ProgressView when loading

struct BeautyCameraButton: View {

    let isLoading: Bool
    let action: () -> Void

    @State private var isPressed    = false
    @State private var shimmerAngle = 0.0

    // Outer / middle / inner diameters
    private let outerD:  CGFloat = 92
    private let middleD: CGFloat = 80
    private let innerD:  CGFloat = 66
    private let shimmerD: CGFloat = 56

    var body: some View {
        ZStack {
            // ── Layer 1: Frosted outer ring ────────────────────────
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: outerD, height: outerD)

            // ── Layer 2: Blush-pink gradient stroke ring ───────────
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            AppTheme.pink.opacity(0.75),
                            AppTheme.pinkLight.opacity(0.25),
                            AppTheme.pinkDark.opacity(0.55),
                            AppTheme.pinkLight.opacity(0.20),
                            AppTheme.pink.opacity(0.75),
                        ],
                        center: .center
                    ),
                    lineWidth: 1.5
                )
                .frame(width: middleD, height: middleD)

            // ── Layer 3: Pearl inner disc ─────────────────────────
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.97),
                            AppTheme.beige.opacity(0.90),
                            AppTheme.beigeMid.opacity(0.82),
                        ],
                        center: UnitPoint(x: 0.36, y: 0.28),
                        startRadius: 2,
                        endRadius: innerD / 1.6
                    )
                )
                .frame(width: innerD, height: innerD)
                // Dimensional shadow: soft pink glow + tight mocha lift
                .shadow(color: AppTheme.pink.opacity(0.32), radius: 14, x: 0, y: 5)
                .shadow(color: AppTheme.mocha.opacity(0.14), radius: 4,  x: 0, y: 2)

            // ── Layer 4: Slow-rotating shimmer arc ────────────────
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.72), Color.white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .frame(width: shimmerD, height: shimmerD)
                .rotationEffect(.degrees(shimmerAngle))

            // ── Layer 5: Center icon or loading spinner ───────────
            if isLoading {
                ProgressView()
                    .tint(AppTheme.mocha)
                    .scaleEffect(0.85)
                    .transition(.opacity)
            } else {
                Image(systemName: "camera.macro")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.mochaDark, AppTheme.mochaLight],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .transition(.opacity)
            }
        }
        .scaleEffect(isPressed ? 0.90 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.62), value: isPressed)
        // Accessibility
        .accessibilityLabel("Capture product photo")
        .accessibilityHint("Takes a photo of the product for ingredient scanning")
        .accessibilityAddTraits(.isButton)
        // Tap + press gesture
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true  }
                .onEnded   { _ in isPressed = false }
        )
        .onTapGesture {
            guard !isLoading else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }
        .disabled(isLoading)
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                shimmerAngle = 360
            }
        }
    }
}

// MARK: — No Ingredients Tip Row

struct NoIngredientsTip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.pinkDark)
                .frame(width: 18)
                .padding(.top, 1)
            Text(text)
                .font(AppTheme.sans(13))
                .foregroundStyle(AppTheme.textMain)
        }
    }
}

#Preview {
    ScannerView()
        .environmentObject(AllergyProfileViewModel())
        .environmentObject(ScanHistoryViewModel())
}
