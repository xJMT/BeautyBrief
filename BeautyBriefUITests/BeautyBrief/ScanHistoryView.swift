import SwiftUI

// ─────────────────────────────────────────────
//  ScanHistoryView  —  past scans log
// ─────────────────────────────────────────────

struct ScanHistoryView: View {

    @EnvironmentObject var historyVM: ScanHistoryViewModel
    @EnvironmentObject var allergyVM: AllergyProfileViewModel
    @State private var showingClearConfirm = false
    @State private var selectedResult: ScanResult?
    @State private var filterAlerts = false

    private var displayedScans: [ScanResult] {
        filterAlerts ? historyVM.scansWithAlerts : historyVM.scans
    }

    var body: some View {
        NavigationStack {
            Group {
                if historyVM.scans.isEmpty {
                    emptyState
                } else {
                    scanList
                }
            }
            .background(AppTheme.beige.ignoresSafeArea())
            .navigationTitle("Scan History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !historyVM.scans.isEmpty {
                        Button {
                            showingClearConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(AppTheme.mocha)
                        }
                    }
                }
            }
            .confirmationDialog("Clear scan history?",
                                isPresented: $showingClearConfirm,
                                titleVisibility: .visible) {
                Button("Clear All", role: .destructive) { historyVM.clearAll() }
            }
            .sheet(item: $selectedResult) { result in
                HistoryDetailSheet(result: result, profile: allergyVM.profile)
                    .environmentObject(allergyVM)
            }
        }
    }

    // MARK: — Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(AppTheme.pinkLight).frame(width: 100, height: 100)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 40))
                    .foregroundStyle(AppTheme.mocha)
            }
            Text("No scans yet")
                .font(AppTheme.serif(22, weight: .semibold))
                .foregroundStyle(AppTheme.mochaDark)
            Text("Your scan history will appear here after you scan your first product.")
                .font(AppTheme.sans(14))
                .foregroundStyle(AppTheme.textSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: — Scan List
    private var scanList: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Text("\(displayedScans.count) scan\(displayedScans.count == 1 ? "" : "s")")
                    .font(AppTheme.sans(13))
                    .foregroundStyle(AppTheme.textSoft)
                Spacer()
                Toggle(isOn: $filterAlerts) {
                    Text("Alerts only")
                        .font(AppTheme.sans(13))
                        .foregroundStyle(AppTheme.textMain)
                }
                .toggleStyle(.button)
                .tint(AppTheme.danger)
                .controlSize(.small)
            }
            .padding(.horizontal, AppTheme.spacingMd)
            .padding(.vertical, 10)
            .background(Color.white)
            .overlay(alignment: .bottom) {
                Divider()
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(displayedScans) { result in
                        ScanHistoryRow(result: result)
                            .padding(.horizontal)
                            .onTapGesture { selectedResult = result }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    historyVM.removeScan(id: result.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: — History Row
struct ScanHistoryRow: View {

    let result: ScanResult

    var body: some View {
        HStack(spacing: 14) {
            // Category icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(result.product.category.color.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: result.product.category.sfSymbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(result.product.category.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(result.product.name)
                    .font(AppTheme.sans(14, weight: .semibold))
                    .foregroundStyle(AppTheme.textMain)
                    .lineLimit(1)
                Text(result.product.brand)
                    .font(AppTheme.sans(12))
                    .foregroundStyle(AppTheme.textSoft)
                Text(result.scannedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(AppTheme.sans(11))
                    .foregroundStyle(AppTheme.mochaLight)
            }

            Spacer()

            // Alert indicators
            VStack(alignment: .trailing, spacing: 4) {
                if !result.allergyMatches.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text("\(result.allergyMatches.count)")
                            .font(AppTheme.sans(11, weight: .bold))
                    }
                    .foregroundStyle(AppTheme.danger)
                }
                if result.expiryWarning {
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .foregroundStyle(AppTheme.warning)
                        .font(.caption)
                }
                if !result.hasAlerts {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.success)
                        .font(.caption)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(AppTheme.beigeDark)
        }
        .padding(14)
        .beautyCard()
    }
}

// MARK: — History Detail Sheet (M-3: analysis computed once in init, not in sheet builder)

private struct HistoryDetailSheet: View {
    let result: ScanResult
    private let analysis: AnalysisResult

    init(result: ScanResult, profile: AllergyProfile) {
        self.result   = result
        self.analysis = IngredientAnalysisService.analyse(product: result.product, profile: profile)
    }

    var body: some View {
        ProductDetailView(
            product:         result.product,
            analysisResult:  analysis,
            batchResult:     nil,
            confidenceScore: result.confidenceScore
        )
    }
}

#Preview {
    let allergyVM = AllergyProfileViewModel()
    ScanHistoryView()
        .environmentObject(ScanHistoryViewModel())
        .environmentObject(allergyVM)
}
