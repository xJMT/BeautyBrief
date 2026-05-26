# BeautyBrief — Deep Debugging Audit Report
**Date:** May 24 2026  
**Files reviewed:** All 46 Swift source files  
**Status of fixes:** 2 bugs fixed inline; remaining items are annotated below.

---

## 🔴 HIGH — Fixed

### H-1 · AllergyProfileViewModel: Profile data lost on every launch (DATA LOSS)
**File:** `AllergyProfileViewModel.swift`

`init()` loaded from `"beautybrief.allergyprofile.v1"`, but `save()` wrote to `"beautybrief.allergyprofile.v2"`. On every launch after the first, the v2 data was silently ignored and the profile reset to v1 (or empty for new installs). All allergens, sensitivities, skin types and blacklisted ingredients set by the user were never persisted.

**Fix applied:** `init` now reads v2 first (normal path), falls back to v1 with migration (writes to v2, deletes v1), and finally falls back to a fresh profile for new installs.

---

### H-2 · ScannerViewModel: Lookup tasks not tracked or cancellable (PHANTOM STATE)
**File:** `ScannerViewModel.swift`

`barcodeDetected()` and `photoTaken()` created bare `Task { }` blocks that were never stored. When the user tapped Cancel → `reset()`, only `enrichmentTask` was cancelled. The in-flight lookup task kept running and would eventually write back to `candidates` and `scanState` on an already-reset ViewModel — causing ghost transitions and incorrect UI states.

Additionally, both branches of the `isHighConfidence` check in `barcodeDetected` did the same thing (dead code).

**Fix applied:** Introduced `lookupTask: Task<Void, Never>?`; both `barcodeDetected` and `photoTaken` now cancel any prior lookup, store the new task, and guard all state writes with `!Task.isCancelled`. `reset()` cancels both `lookupTask` and `enrichmentTask`.

---

## 🟠 MEDIUM — Action recommended

### M-1 · ProductDatabaseService + ProductWebSearchService: Heavy work on @MainActor
**Files:** `ProductDatabaseService.swift`, `ProductWebSearchService.swift`

Both services are marked `@MainActor`. URLSession awaits correctly suspend off the main thread, but all code *between* those awaits — including the `MockData.allProducts.first { ... }` string-matching loops and the `NSRegularExpression` HTML-stripping in `stripHTML()` — runs on the main thread. On a product that hits steps 5–7 of the barcode chain (all APIs return empty), the main thread processes 3+ OBF name-search rounds plus web-HTML parsing while the scan spinner is showing.

**Recommendation:** Remove `@MainActor` from both services. `ProductDatabaseService` has a `cache` dict that would need an actor or lock, but since it's only written after network I/O (already on a background thread) a simple `nonisolated` annotation + `@MainActor` targeted only on `cache` access would suffice.

---

### M-2 · ScannerView: enrichTimer keeps running after tab switch
**File:** `ScannerView.swift` (lines 125–132)

`enrichTimer` is a stored `Task` that increments `enrichSeconds` every second while in `.enriching` state. When the user switches to another tab mid-enrichment, the view is kept in the hierarchy (tab bar), so the timer is never cancelled and the counter keeps climbing. Returning to the scanner tab shows an inflated elapsed time (e.g. "Still searching… (45s)") even if the actual enrich only started 2 s ago.

**Recommendation:** Add `.onDisappear { enrichTimer?.cancel(); enrichTimer = nil; enrichSeconds = 0 }` to `ScannerView`.

---

### M-3 · ScanHistoryView: IngredientAnalysisService.analyse runs in view builder
**File:** `ScanHistoryView.swift` (lines 49–58)

Each time the user taps a scan history row, the `.sheet` content builder calls `IngredientAnalysisService.analyse(product:profile:)` synchronously on the main thread. For products with 80+ ingredients this can cause a 30–80 ms stall and a visible sheet animation hitch on older devices (iPhone XS and earlier).

**Recommendation:** Move the analysis into a `Task` triggered by `.onAppear` of `ProductDetailView`, or pass a pre-computed `AnalysisResult` from the scan session if available. Using `@State var analysis: AnalysisResult?` with a `ProgressView` fallback is the cleanest approach.

---

### M-4 · CommunityViewModel: trendingProducts recomputed on every access
**File:** `CommunityViewModel.swift` (lines 48–64)

`trendingProducts` is a computed property that filters all posts by date, groups by product name, sorts, and slices on every call. It is bound into the Community feed header which can trigger dozens of evaluations per scroll frame.

**Recommendation:** Replace with a stored property updated only in `load()` and `submit()`, or cache the result with a simple dirty flag.

---

## 🟡 LOW — Note for future sprints

### L-1 · API keys hardcoded as string fallbacks in source
**File:** `ProductDatabaseService.swift` (APIKeys enum, lines 519–537)

`googleVision` and `inciAPI` have hardcoded fallback keys that will be compiled into the binary and visible in version control. The environment-variable pattern is correct for CI, but the fallback strings should not be real production keys.

**Recommendation:** Move production keys to a `.xcconfig` excluded from git (add to `.gitignore`), and replace the inline fallbacks with `""` so a missing key surfaces as a no-op rather than silently using a shared key.

---

### L-2 · CommunityViewModel: no reaction dedup
**File:** `CommunityViewModel.swift` (react function, lines 121–130)

There is no per-user guard on `react(to:reaction:)`. A user can tap Heart, Heart, Heart and the count increments by 3. The CloudKit `react` call is also fire-and-forget — if the network is slow, multiple taps generate multiple in-flight mutations.

**Recommendation:** Track which post IDs the user has reacted to in a `Set<String>` (persisted to UserDefaults) and early-return in `react()` if already reacted.

---

### L-3 · ScanHeroButton: 29 animated stars with .plusLighter on older GPUs
**File:** `ScannerView.swift` (ScanHeroButton, lines 966–990)

29 `FivePointedStar` shapes each with `.blendMode(.plusLighter)` and `rotationEffect` animations targeting 6 different `@State` vars. On A11/A12 devices (iPhone X–XS) this combination can push the GPU above the 16 ms frame budget when the idle screen first appears, causing a 1–2 frame drop.

**Recommendation:** Reduce to 15–18 stars, or use a single `Canvas` draw pass instead of 29 individual view nodes.

---

### L-4 · FDARecallService.swift is an empty stub
**File:** `FDARecallService.swift`

The file is intentionally empty with a comment to delete it. It is still in the compile target, producing a zero-symbol object file on every build.

**Recommendation:** Right-click the file in Xcode → Delete → Move to Trash.

---

### L-5 · OpenBeautyFactsService: UUID fallback barcode in searchByName
**File:** `OpenBeautyFactsService.swift` (line 100)

```swift
.compactMap { buildProduct(from: $0, barcode: $0.code ?? UUID().uuidString) }
```

When a search result has no `code` field (barcode), a random UUID is assigned as the product ID. This means the same product returned by two separate name searches will have two different IDs and will never hit the in-memory cache in `ProductDatabaseService`. Low impact but wastes a cache slot.

---

### L-6 · AllergyProfileViewModel: v1 UserDefaults key not cleaned up in clearAll()
**File:** `AllergyProfileViewModel.swift` (`clearAll()`)

`clearAll()` resets `profile = AllergyProfile()` and triggers `save()` (writing a blank profile to v2), but does not remove the v1 key. If a user clears their profile and reinstalls the app, the old v1 data will be loaded again during migration. Negligible in practice but inconsistent.

---

## ✅ Already Solid

- **ScanHistoryViewModel** — race condition guard (`hasPendingWrites`) is correct; async load with `Task.detached` properly hands off to background and rejoins MainActor.
- **OpenBeautyFactsService** — not `@MainActor`; parallel `async let` across OBF/OFF/OPF is efficient; parenthetical sub-ingredient expansion is a nice correctness detail.
- **BatchCodeService** — all brand-specific decoders guard correctly; no force-unwraps remain.
- **IngredientAnalysisService** — clean single-pass analysis loop; scoring formula is well-bounded (max 5, min 100).
- **CommunityService** — CloudKit correctly isolated; no CloudKit types leak into ViewModel or View layers.
- **ProductScoringService** — 8 independent scoring algorithms, no shared mutable state.
- **ScannerView → ProductDetailView sheet** — history save (`historyVM.addScan`) correctly in `onDismiss` before `vm.reset()`, so no race.
- **AppTheme** — single source of truth for all colors; no inline hex values in Views (except ScannerView's wordmark blush, which is intentional).
