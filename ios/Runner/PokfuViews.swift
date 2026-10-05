import Foundation
import SwiftUI
import UIKit
import WebKit

struct AdaptiveNavigation<Content: View>: View {
    let title: String
    let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack { content() }
                    .navigationTitle(title)
            } else {
                NavigationView { content() }
                    .navigationTitle(title)
                    .navigationViewStyle(.stack)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: PokfuAppState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab: Int

    init(defaultTab: Int = 0) { _selectedTab = State(initialValue: defaultTab) }

    var body: some View {
        Group {
            if sizeClass == .regular {
                iPadRoot
            } else {
                phoneRoot
            }
        }
        // A SwiftUI root view can otherwise size itself to the intrinsic height
        // of the current tab on newer iOS simulator runtimes. That leaves the
        // hosting window's background visible above and below the app content.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .tint(.pokfuBlue)
        .preferredColorScheme(state.settings.theme)
        .onOpenURL { url in handle(url) }
        .onChange(of: selectedTab) { _ in state.settings.set(SettingKey.defaultTab, selectedTab) }
    }

    private var phoneRoot: some View {
        TabView(selection: $selectedTab) {
            EventsView().tabItem { Label("Events", systemImage: selectedTab == 0 ? "calendar.circle.fill" : "calendar") }.tag(0)
            CoursesView().tabItem { Label("Courses", systemImage: selectedTab == 1 ? "books.vertical.fill" : "books.vertical") }.tag(1)
            CalendarView().tabItem { Label("Calendar", systemImage: "calendar.day.timeline.left") }.tag(2)
            SettingsView().tabItem { Label("Settings", systemImage: selectedTab == 3 ? "gearshape.fill" : "gearshape") }.tag(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iPadRoot: some View {
        NavigationView {
            List {
                Button { selectedTab = 0 } label: { Label("Events", systemImage: "calendar") }
                    .listRowBackground(selectedTab == 0 ? Color.pokfuBlue.opacity(0.14) : .clear)
                Button { selectedTab = 1 } label: { Label("Courses", systemImage: "books.vertical") }
                    .listRowBackground(selectedTab == 1 ? Color.pokfuBlue.opacity(0.14) : .clear)
                Button { selectedTab = 2 } label: { Label("Calendar", systemImage: "calendar.day.timeline.left") }
                    .listRowBackground(selectedTab == 2 ? Color.pokfuBlue.opacity(0.14) : .clear)
                Button { selectedTab = 3 } label: { Label("Settings", systemImage: "gearshape") }
                    .listRowBackground(selectedTab == 3 ? Color.pokfuBlue.opacity(0.14) : .clear)
            }
            .listStyle(.sidebar)
            .navigationTitle("Pokfu")
            Group {
                switch selectedTab {
                case 1: CoursesView()
                case 2: CalendarView()
                case 3: SettingsView()
                default: EventsView()
                }
            }
        }
        .navigationViewStyle(.columns)
    }

    private func handle(_ url: URL) {
        if url.host == "action", url.queryItems["name"] == "complete", let id = Int(url.queryItems["id"] ?? "") {
            if let event = state.moodle.events.first(where: { $0.id == id }), !event.isCompleted { state.moodle.toggleCompletion(event) }
        } else if [PokfuBrand.urlScheme, PokfuBrand.legacyURLScheme].contains(url.scheme),
                  url.host?.hasPrefix("token=") == true || url.queryItems["token"] != nil {
            Task { await state.moodle.finishAuthentication(url.absoluteString) }
        }
    }
}

struct LoginPrompt: View {
    @EnvironmentObject private var state: PokfuAppState
    let title: String

    var body: some View {
        PokfuEmptyView(title: title, message: "Connect Pokfu to Moodle to sync courses and deadlines.", actionTitle: "Connect to Moodle", action: state.moodle.startAuthentication)
    }
}

struct PokfuEmptyView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct EventsView: View {
    @EnvironmentObject private var state: PokfuAppState
    @Environment(\.openURL) private var openURL
    @State private var searchText = ""
    @State private var showReminders = false
    @State private var showMore = false
    @State private var showNewEvent = false
    @State private var showArchive = false
    @State private var showTutor = false

    private var filteredGroups: [(String, [MoodleEvent])] {
        state.moodle.groupedEvents().map { key, events in
            (key, searchText.isEmpty ? events : events.filter { $0.name.localizedCaseInsensitiveContains(searchText) || (state.moodle.course(for: $0)?.fullname.localizedCaseInsensitiveContains(searchText) ?? false) })
        }.filter { !$0.1.isEmpty }
    }

    var body: some View {
        AdaptiveNavigation("Events") {
            Group {
                if !state.moodle.isLoggedIn {
                    LoginPrompt(title: "Connect to Moodle")
                } else if filteredGroups.isEmpty {
                    PokfuEmptyView(title: "No Upcoming Events", message: "Amazing! There are currently no upcoming events for you.")
                } else {
                    List {
                        if state.moodle.status == .error, let message = state.moodle.errorMessage {
                            Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                        }
                        ForEach(filteredGroups, id: \.0) { group, events in
                            Section(group) {
                                ForEach(events) { event in EventRow(event: event) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await state.moodle.refresh() }
                }
            }
            .searchable(text: $searchText, prompt: "Search events, courses, and reminders")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if state.moodle.status == .updating { ProgressView() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showTutor = true } label: { Image(systemName: "sparkles") }
                        .accessibilityLabel("Moodle tutor")
                    Button { showArchive = true } label: { Image(systemName: "archivebox") }
                    Button { showReminders = true } label: { Image(systemName: "bell") }
                    Button { showMore = true } label: { Image(systemName: "ellipsis.circle") }
                    Button { showNewEvent = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showReminders) { RemindersView() }
            .sheet(isPresented: $showArchive) { ArchivedEventsView() }
            .sheet(isPresented: $showMore) { EventOptionsView() }
            .sheet(isPresented: $showNewEvent) { CustomEventEditor(event: .custom()) }
            .sheet(isPresented: $showTutor) { MoodleTutorView(moodle: state.moodle, ai: state.ai) }
            .alert("Moodle", isPresented: Binding(get: { state.moodle.errorMessage != nil }, set: { if !$0 { state.moodle.clearError() } })) {
                Button("OK", role: .cancel) { state.moodle.clearError() }
            } message: { Text(state.moodle.errorMessage ?? "") }
        }
    }
}

struct MoodleTutorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var model: MoodleTutorViewModel
    @State private var showShare = false

    let moodle: MoodleStore
    let ai: AIProviderStore

    init(moodle: MoodleStore, ai: AIProviderStore) {
        self.moodle = moodle
        self.ai = ai
        _model = StateObject(wrappedValue: MoodleTutorViewModel(moodle: moodle, ai: ai))
    }

    var body: some View {
        AdaptiveNavigation("Moodle Tutor") {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: ai.activeProvider != nil ? "network" : (PokfuAIAvailability.appleIntelligenceAvailable ? "apple.intelligence" : "square.and.arrow.up"))
                        .foregroundStyle(Color.pokfuBlue)
                    Text(ai.activeProviderName.map { "Using \($0)" } ?? PokfuAIAvailability.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.thinMaterial)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if model.messages.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("Ask about your Moodle courses", systemImage: "sparkles")
                                        .font(.title3.weight(.semibold))
                                    Text("Pokfu searches live Moodle courses and cached materials first, then uses your selected AI provider. Relevant PDF text and Moodle sources are included in the request. You can change providers in Settings → AI Providers.")
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.top, 28)
                            }

                            ForEach(model.messages) { message in
                                MoodleTutorBubble(message: message)
                                    .id(message.id)
                            }

                            if !model.results.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Moodle sources")
                                        .font(.headline)
                                    ForEach(model.results.prefix(8)) { result in
                                        Button {
                                            Task {
                                                if let url = await moodle.openMoodleURL(result.url ?? result.contexturl) {
                                                    openURL(url)
                                                }
                                            }
                                        } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(result.displayTitle)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(nil)
                                                if !result.displayContent.isEmpty {
                                                    Text(result.displayContent)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(3)
                                                }
                                                if !result.coursefullname.isEmpty {
                                                    Text(result.coursefullname)
                                                        .font(.caption2)
                                                        .foregroundStyle(Color.pokfuBlue)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(12)
                                            .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 8)
                            }

                            if !model.attachments.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Files included when you share", systemImage: "paperclip")
                                        .font(.headline)
                                    ForEach(model.attachments) { attachment in
                                        HStack(spacing: 10) {
                                            Image(systemName: attachment.fileName.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "doc")
                                                .foregroundStyle(Color.pokfuBlue)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(attachment.fileName)
                                                    .font(.subheadline.weight(.semibold))
                                                    .lineLimit(2)
                                                Text(attachment.courseName)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(10)
                                        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                }
                                .padding(.top, 8)
                            }

                            if let attachmentMessage = model.attachmentMessage {
                                Label(attachmentMessage, systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if let errorMessage = model.errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }

                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding()
                    }
                    .onChange(of: model.messages.count) { _ in
                        guard let last = model.messages.last else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }

                Divider()
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Ask about Moodle…", text: $model.query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit { Task { await model.ask() } }

                    if model.isWorking {
                        ProgressView()
                            .frame(width: 34, height: 34)
                    } else {
                        Button {
                            Task { await model.ask() }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title)
                        }
                        .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Ask tutor")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(!model.canShare)
                    .accessibilityLabel("Share Moodle context")

                    Button {
                        model.clearConversation()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .disabled(model.messages.isEmpty)
                    .accessibilityLabel("Clear conversation")
                }
            }
            .sheet(isPresented: $showShare) {
                SystemShareSheet(items: model.shareItems)
            }
        }
    }
}

private struct MoodleTutorBubble: View {
    let message: MoodleTutorMessage

    var body: some View {
        HStack {
            if message.role == .assistant { Spacer(minLength: 30) }
            Text(message.text)
                .font(.body)
                .foregroundStyle(message.role == .assistant ? Color.primary : Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.role == .assistant ? Color.secondary.opacity(0.12) : Color.pokfuBlue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if message.role == .user { Spacer(minLength: 30) }
        }
    }
}

private struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct EventRow: View {
    @EnvironmentObject private var state: PokfuAppState
    let event: MoodleEvent

    var body: some View {
        NavigationLink(destination: EventDetailView(event: event)) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(state.moodle.course(for: event)?.color ?? .secondary)
                    .frame(width: 5)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(state.moodle.course(for: event)?.courseCode ?? (event.isCustom ? "CUSTOM" : "EVENT"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(state.moodle.course(for: event)?.color ?? .secondary)
                        Spacer()
                        Text(event.time, style: .relative)
                            .font(.caption)
                            .foregroundStyle(event.expired ? .secondary : .primary)
                    }
                    CrossedOffText(
                        text: event.name,
                        isCrossedOff: event.isCompleted,
                        font: .body.weight(.semibold),
                        color: event.isCompleted && state.settings.bool(SettingKey.greyOutCompleted, default: true) ? .secondary : .primary
                    )
                    Text(event.time, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 5)
            .contextMenu {
                Button(event.isCompleted ? "Mark as Open" : "Mark as Completed", systemImage: event.isCompleted ? "circle" : "checkmark.circle") {
                    state.moodle.toggleCompletion(event)
                }
                Button(event.isArchived ? "Unarchive" : "Archive", systemImage: event.isArchived ? "tray.and.arrow.up" : "archivebox") {
                    state.moodle.setArchived(event, archived: !event.isArchived)
                    DispatchQueue.main.async { state.reminders.rescheduleAll() }
                }
            }
        }
    }
}

struct ArchivedEventsView: View {
    @EnvironmentObject private var state: PokfuAppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if state.moodle.archivedEvents.isEmpty {
                    PokfuEmptyView(title: "No Archived Events", message: "Events you archive from the home page will appear here.")
                } else {
                    List(state.moodle.archivedEvents) { event in
                        EventRow(event: event)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Archive")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct EventOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: PokfuAppState

    var body: some View {
        NavigationView {
            Form {
                Section("Group By") {
                    Picker("Group By", selection: Binding(get: { state.settings.int(SettingKey.eventGrouping) }, set: { state.settings.set(SettingKey.eventGrouping, $0) })) {
                        ForEach(EventGrouping.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Sync with Moodle") { Task { await state.moodle.refresh(); dismiss() } }
                    Button("Add Custom Event") { dismiss() }
                }
            }
            .navigationTitle("Events")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct EventDetailView: View {
    @EnvironmentObject private var state: PokfuAppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showEditor = false
    let event: MoodleEvent

    private var currentEvent: MoodleEvent { state.moodle.events.first(where: { $0.id == event.id }) ?? event }
    private var course: MoodleCourse? { state.moodle.course(for: currentEvent) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    if currentEvent.isCustom { Label("Custom Event", systemImage: "calendar.badge.plus").font(.subheadline.weight(.semibold)).foregroundStyle(course?.color ?? .accentColor) }
                    if let course { Text(course.displayname.isEmpty ? course.fullname : course.displayname).font(.headline).foregroundStyle(course.color).lineLimit(nil) }
                    CrossedOffText(text: currentEvent.name, isCrossedOff: currentEvent.isCompleted, font: .largeTitle.weight(.bold), color: currentEvent.isCompleted ? .secondary : .primary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("DUE IN").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(remainingText).font(.title3.weight(.bold)).foregroundStyle(Color.pokfuBlue)
                    Text(currentEvent.time, format: .dateTime.weekday(.wide).month().day().hour().minute()).foregroundStyle(.secondary)
                }
                if !currentEvent.description.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DESCRIPTION").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        HTMLContentView(html: currentEvent.description)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 32)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("REMINDERS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    let applied = state.reminders.applied(to: currentEvent)
                    if applied.isEmpty { Text("No reminders applied to this event.").foregroundStyle(.secondary) }
                    ForEach(applied) { reminder in Text(reminder.title ?? "Reminder").foregroundStyle(.primary).lineLimit(nil) }
                }
                VStack(spacing: 10) {
                    Button(currentEvent.isCompleted ? "Mark as Open" : "Mark as Completed", systemImage: currentEvent.isCompleted ? "circle" : "checkmark.circle") {
                        state.moodle.toggleCompletion(currentEvent)
                        dismiss()
                    }
                    if currentEvent.isCustom {
                        Button("Edit Custom Event", systemImage: "square.and.pencil") { showEditor = true }
                    } else if let url = currentEvent.url {
                        Button("Check Event on Moodle", systemImage: "arrow.up.right.square") { Task { if let url = await state.moodle.openMoodleURL(url) { openURL(url) } } }
                    }
                    if #available(iOS 16.1, *), !currentEvent.isCompleted {
                        Button("Add to Lock Screen", systemImage: "pin") { Task { await WidgetBridge.shared.pin(event: currentEvent, course: course) } }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) { CustomEventEditor(event: currentEvent) }
    }

    private var remainingText: String {
        let interval = max(0, Int(currentEvent.remainingTime))
        return "\(interval / 86400)d \((interval / 3600) % 24)h remaining"
    }
}

struct CustomEventEditor: View {
    @EnvironmentObject private var state: PokfuAppState
    @Environment(\.dismiss) private var dismiss
    @State private var event: MoodleEvent
    @State private var date: Date
    @State private var title: String
    @State private var selectedCourse: MoodleCourse?

    init(event: MoodleEvent) {
        _event = State(initialValue: event)
        _date = State(initialValue: event.time)
        _title = State(initialValue: event.name)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)
                    Picker("Course", selection: Binding(get: { selectedCourse?.id ?? -1 }, set: { id in selectedCourse = state.moodle.courses.first { $0.id == id } })) {
                        Text("No Associated Course").tag(-1)
                        ForEach(state.moodle.courses) { course in Text(course.courseCode).tag(course.id) }
                    }
                    DatePicker("Due", selection: $date, in: Date()...)
                }
                if !event.name.isEmpty {
                    Section { Button("Delete Custom Event", role: .destructive) { state.moodle.removeEvent(event); dismiss() } }
                }
            }
            .navigationTitle(event.name.isEmpty ? "New Custom Event" : "Edit Event")
            .onAppear {
                if selectedCourse == nil, let id = event.courseid {
                    selectedCourse = state.moodle.courses.first { $0.id == id }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }

    private func save() {
        event.name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.timestart = date.epoch
        event.courseid = selectedCourse?.id
        state.moodle.addCustomEvent(event)
        dismiss()
    }
}

struct CoursesView: View {
    @EnvironmentObject private var state: PokfuAppState
    @State private var searchText = ""
    @State private var showFavorites = false
    @State private var showFilters = false

    private var filtered: [MoodleCourse] {
        var courses = state.moodle.courses
            .filter { !showFavorites || $0.isFavorite }
            .filter { searchText.isEmpty || $0.fullname.localizedCaseInsensitiveContains(searchText) }
        if CourseFiltering(rawValue: state.settings.int(SettingKey.courseFiltering)) == .latestSemester,
           let latest = courses.compactMap(\.startdate).max() {
            courses = courses.filter { $0.startdate == latest }
        }
        if CourseSorting(rawValue: state.settings.int(SettingKey.courseSorting)) == .lastAccessed {
            return courses.sorted { ($0.lastaccess ?? 0) > ($1.lastaccess ?? 0) }
        }
        return courses.sorted { $0.courseCode.localizedCaseInsensitiveCompare($1.courseCode) == .orderedAscending }
    }

    var body: some View {
        AdaptiveNavigation("Courses") {
            Group {
                if !state.moodle.isLoggedIn { LoginPrompt(title: "Connect to Moodle") }
                else if filtered.isEmpty { PokfuEmptyView(title: "No Courses", message: showFavorites ? "Mark courses as favorites to see them here." : "Your Moodle courses will appear here.") }
                else {
                    List(filtered) { course in
                        NavigationLink(destination: CourseDetailView(course: course)) { CourseRow(course: course) }
                            .swipeActions(edge: .leading) { Button { state.moodle.toggleFavorite(course) } label: { Label("Favorite", systemImage: course.isFavorite ? "star.slash" : "star") }.tint(.yellow) }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await state.moodle.refresh(forceEvents: false) }
                }
            }
            .searchable(text: $searchText)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button { showFavorites.toggle() } label: { Image(systemName: showFavorites ? "star.fill" : "star") } }
                ToolbarItem(placement: .navigationBarTrailing) { Button { showFilters = true } label: { Image(systemName: "line.3.horizontal.decrease.circle") } }
            }
            .sheet(isPresented: $showFilters) { CourseFilterView(showFavorites: $showFavorites) }
        }
    }
}

struct CourseRow: View {
    let course: MoodleCourse
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).fill(course.color).frame(width: 12, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(course.courseCode).font(.headline).foregroundStyle(course.color)
                Text(course.nameWithoutCode.isEmpty ? course.fullname : course.nameWithoutCode)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            if course.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
        }
    }
}

struct CourseFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: PokfuAppState
    @Binding var showFavorites: Bool
    var body: some View {
        NavigationView {
            Form {
                Toggle("Show favorites only", isOn: $showFavorites)
                Picker("Sort By", selection: Binding(get: { state.settings.int(SettingKey.courseSorting) }, set: { state.settings.set(SettingKey.courseSorting, $0) })) {
                    ForEach(CourseSorting.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Filter By", selection: Binding(get: { state.settings.int(SettingKey.courseFiltering) }, set: { state.settings.set(SettingKey.courseFiltering, $0) })) {
                    ForEach(CourseFiltering.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }
            .navigationTitle("Courses")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct CourseDetailView: View {
    @EnvironmentObject private var state: PokfuAppState
    @Environment(\.openURL) private var openURL
    let course: MoodleCourse
    @State private var selection = 0
    @State private var contents: [MoodleCourseSection] = []
    @State private var grades: [MoodleCourseGrade] = []
    @State private var isLoading = true
    @State private var contentError: String?
    @State private var gradeError: String?
    @State private var materialError: String?
    @State private var selectedMaterial: CourseMaterialDestination?
    @State private var isOpeningMaterial = false

    private var displayedGrades: [MoodleCourseGrade] {
        grades.filter { $0.isRenderable }
    }

    var body: some View {
        VStack {
            Picker("Course View", selection: $selection) { Text("Contents").tag(0); Text("Grades").tag(1) }.pickerStyle(.segmented).padding(.horizontal)
            if isLoading { ProgressView().frame(maxHeight: .infinity) }
            else if selection == 0 {
                if contents.filter({ !$0.isEmpty }).isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.book.closed")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Course Content")
                            .font(.headline)
                        Text(contentError ?? "Moodle did not return any visible sections for this course.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load(force: true) } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(contents.filter { !$0.isEmpty }) { section in
                        Section(section.name.isEmpty ? "Section \(section.section)" : section.name) {
                            if !section.summary.isEmpty {
                                HTMLContentView(html: section.summary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(minHeight: 28)
                            }
                            ForEach(section.modules) { module in
                                Button { openModule(module) } label: {
                                    Label(module.name.isEmpty ? "Course material" : module.name,
                                          systemImage: module.hasDownloadableFile ? "doc" : "link")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            } else {
                List {
                    if let gradeError {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Grades couldn’t be loaded", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                            Text(gradeError)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Retry") {
                                Task { await load(force: true) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 8)
                    } else if displayedGrades.isEmpty {
                        Text("No grades are available for this course.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(displayedGrades.enumerated()), id: \.offset) { item in
                            let grade = item.element
                            CourseGradeRow(grade: grade, tint: course.color)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(course.courseCode)
        .task { await load() }
        .refreshable { await load(force: true) }
        .overlay {
            if isOpeningMaterial {
                ProgressView("Opening material…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Course material", isPresented: Binding(get: { materialError != nil }, set: { if !$0 { materialError = nil } })) {
            Button("OK", role: .cancel) { materialError = nil }
        } message: {
            Text(materialError ?? "Unable to open this material.")
        }
        .sheet(item: $selectedMaterial) { material in
            CourseMaterialView(title: material.title, url: material.url)
        }
    }

    private func load(force: Bool = false) async {
        isLoading = true
        contentError = nil
        gradeError = nil
        if !force, let cached = course.cachedContents {
            contents = cached
        } else if let loaded = await state.moodle.loadContents(for: course, force: force) {
            contents = loaded
        } else {
            contents = []
            contentError = "Moodle could not load this course’s contents. Check your connection and try again."
        }
        guard !Task.isCancelled else {
            isLoading = false
            return
        }
        do {
            grades = try await state.moodle.loadGrades(for: course)
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            grades = []
            gradeError = error.localizedDescription.isEmpty
                ? "Moodle returned an unexpected grades response."
                : error.localizedDescription
        }
        isLoading = false
    }

    private func openModule(_ module: MoodleCourseModule) {
        guard module.url != nil || module.fileURL != nil else {
            materialError = "This course material does not include a valid Moodle link."
            return
        }

        Task {
            isOpeningMaterial = true
            defer { isOpeningMaterial = false }
            guard let url = await state.moodle.materialURL(for: module) else {
                materialError = "Moodle could not create a signed link for this material."
                return
            }
            if state.settings.bool(SettingKey.openResourceInBrowser) {
                openURL(url)
            } else {
                selectedMaterial = CourseMaterialDestination(
                    title: module.name.isEmpty ? "Course Material" : module.name,
                    url: url
                )
            }
        }
    }
}

private struct CourseGradeRow: View {
    let grade: MoodleCourseGrade
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(grade.title)
                        .font(.headline)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(grade.displayGrade == "-" || grade.displayGrade.isEmpty ? "—" : grade.displayGrade)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if !grade.displayPercentage.isEmpty {
                        Text(grade.displayPercentage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }

            if !grade.displayRange.isEmpty {
                GradeDetail(label: "Range", value: grade.displayRange)
            }

            if !grade.displayWeight.isEmpty || !grade.displayContribution.isEmpty {
                HStack(alignment: .top, spacing: 24) {
                    if !grade.displayWeight.isEmpty {
                        GradeDetail(label: "Weight", value: grade.displayWeight)
                    }
                    if !grade.displayContribution.isEmpty {
                        GradeDetail(label: "Course contribution", value: grade.displayContribution)
                    }
                }
            }

            if let feedback = grade.displayFeedback {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.secondary)
                    Text(feedback)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct GradeDetail: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CourseMaterialDestination: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

private final class MoodleMaterialWebViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var progress = 0.0
    @Published var pageTitle = ""
    @Published var errorMessage: String?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL?

    weak var webView: WKWebView?

    func reload() {
        errorMessage = nil
        isLoading = true
        webView?.reload()
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
}

private struct CourseMaterialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var model = MoodleMaterialWebViewModel()

    let title: String
    let url: URL

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                MoodleMaterialWebView(url: url, model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if model.isLoading {
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                        .tint(.pokfuBlue)
                        .background(Color(uiColor: .systemBackground))
                }

                if let errorMessage = model.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("Couldn’t load this material")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { model.reload() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .frame(maxWidth: 360)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 18) {
                    Button { model.goBack() } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(!model.canGoBack)

                    Button { model.goForward() } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .disabled(!model.canGoForward)

                    Spacer()

                    Button { model.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                    }

                    Button { openURL(model.currentURL ?? url) } label: {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("Open in Safari")
                }
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle(model.pageTitle.isEmpty ? title : model.pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct MoodleMaterialWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var model: MoodleMaterialWebViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let responsiveCSS = """
        (function() {
            var meta = document.querySelector('meta[name=viewport]');
            if (!meta) {
                meta = document.createElement('meta');
                meta.name = 'viewport';
                document.head.appendChild(meta);
            }
            meta.content = 'width=device-width, initial-scale=1, maximum-scale=5';
            var style = document.createElement('style');
            style.textContent = 'html, body { max-width: 100%; overflow-x: hidden; } img, video, iframe { max-width: 100% !important; height: auto !important; } table { max-width: 100% !important; }';
            document.head.appendChild(style);
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: responsiveCSS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        context.coordinator.attach(to: webView, url: url)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.load(url: url, in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: MoodleMaterialWebViewModel
        weak var webView: WKWebView?
        var loadedURL: URL?
        var progressObservation: NSKeyValueObservation?

        init(model: MoodleMaterialWebViewModel) {
            self.model = model
        }

        func attach(to webView: WKWebView, url: URL) {
            self.webView = webView
            model.webView = webView
            progressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in
                let progress = view.estimatedProgress
                // WKWebView can deliver the initial KVO value while SwiftUI is
                // updating the representable. Defer the published mutation
                // to the next main-loop turn to avoid an AttributeGraph
                // "setting value during update" precondition.
                DispatchQueue.main.async { [weak self] in
                    self?.model.progress = progress
                }
            }
            load(url: url, in: webView)
        }

        func load(url: URL, in webView: WKWebView) {
            loadedURL = url
            model.currentURL = url
            model.errorMessage = nil
            model.isLoading = true
            model.progress = 0
            webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 45))
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            model.isLoading = true
            model.errorMessage = nil
            updateNavigationState(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            model.isLoading = false
            model.pageTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            model.currentURL = webView.url ?? loadedURL
            updateNavigationState(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            finishWithError(error, webView: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
            finishWithError(error, webView: webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let targetURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if ["http", "https"].contains(targetURL.scheme?.lowercased() ?? "") {
                decisionHandler(.allow)
            } else if UIApplication.shared.canOpenURL(targetURL) {
                UIApplication.shared.open(targetURL)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.cancel)
            }
        }

        private func finishWithError(_ error: Error, webView: WKWebView) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            model.isLoading = false
            model.errorMessage = error.localizedDescription
            updateNavigationState(webView)
        }

        private func updateNavigationState(_ webView: WKWebView) {
            model.canGoBack = webView.canGoBack
            model.canGoForward = webView.canGoForward
        }
    }
}

struct CalendarView: View {
    @EnvironmentObject private var state: PokfuAppState
    @State private var month = Date()
    @State private var selected = Date()

    var body: some View {
        AdaptiveNavigation("Calendar") {
            Group {
                if !state.moodle.isLoggedIn {
                    LoginPrompt(title: "Connect to Moodle")
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }
                            Spacer()
                            Text(month, format: .dateTime.month(.wide).year()).font(.headline)
                            Spacer()
                            Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }
                        }
                        .padding()
                        CalendarGrid(month: month, selected: $selected, workload: state.moodle.workload(on:), events: state.moodle.events(on:))
                            .padding(.horizontal)
                        List {
                            Section("Events on \(selected.formatted(date: .abbreviated, time: .omitted))") {
                                let events = state.moodle.events(on: selected)
                                if events.isEmpty { Text("No events found for the selected day.").foregroundStyle(.secondary) }
                                ForEach(events) { event in NavigationLink(destination: EventDetailView(event: event)) { Text(event.name) } }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
        }
    }
}

struct CalendarGrid: View {
    let month: Date
    @Binding var selected: Date
    let workload: (Date) -> Double
    let events: (Date) -> [MoodleEvent]
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { Text($0.prefix(1)).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            ForEach(days, id: \.self) { day in
                Button { selected = day } label: {
                    VStack(spacing: 3) {
                        Text(day, format: .dateTime.day()).font(.callout.weight(Calendar.current.isDate(day, inSameDayAs: selected) ? .bold : .regular))
                        Circle().fill(workload(day) > 1 ? Color.orange : .green).frame(width: 5, height: 5).opacity(events(day).isEmpty ? 0 : 1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Calendar.current.isDate(day, inSameDayAs: selected) ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var days: [Date] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month), let range = Calendar.current.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = Calendar.current.component(.weekday, from: interval.start) - Calendar.current.firstWeekday
        let leading = (firstWeekday + 7) % 7
        let prefix = (0..<leading).compactMap { Calendar.current.date(byAdding: .day, value: -leading + $0, to: interval.start) }
        let current = range.compactMap { Calendar.current.date(byAdding: .day, value: $0 - 1, to: interval.start) }
        let trailingCount = (7 - (prefix.count + current.count) % 7) % 7
        let trailing = (0..<trailingCount).compactMap { Calendar.current.date(byAdding: .day, value: $0 + current.count, to: interval.start) }
        return prefix + current + trailing
    }
}

struct RemindersView: View {
    @EnvironmentObject private var state: PokfuAppState
    @Environment(\.dismiss) private var dismiss
    @State private var editing: EventReminder?
    @State private var permissionWarning = false

    var body: some View {
        NavigationView {
            List {
                if permissionWarning { Section { Label("Notifications are disabled. Enable them in Settings for reminders to work.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) } }
                Section {
                    ForEach(state.reminders.reminders) { reminder in
                        Button { editing = reminder } label: { Label { VStack(alignment: .leading) { Text(reminder.title ?? "Reminder"); Text(reminder.timingDescription).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: reminder.disabled ?? false ? "bell.slash.fill" : "bell.fill") } }
                    }
                    .onDelete { offsets in offsets.map { state.reminders.reminders[$0] }.forEach(state.reminders.remove) }
                }
                Section { Button { editing = state.reminders.create() } label: { Label("Add Reminder", systemImage: "plus") } }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Reminders")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { permissionWarning = !(await state.reminders.requestPermission()) }
            .sheet(item: $editing) { reminder in ReminderEditor(reminder: reminder) }
        }
    }
}

struct ReminderEditor: View {
    @EnvironmentObject private var state: PokfuAppState
    @Environment(\.dismiss) private var dismiss
    @State private var reminder: EventReminder
    @State private var title: String
    @State private var showExactTime: Bool

    init(reminder: EventReminder) { _reminder = State(initialValue: reminder); _title = State(initialValue: reminder.title ?? ""); _showExactTime = State(initialValue: reminder.unit.rawValue >= ReminderUnit.days.rawValue) }

    var body: some View {
        NavigationView {
            Form {
                Section("Reminder") {
                    TextField("Title", text: $title)
                    Stepper("\(reminder.amount) \(reminder.unit.title)", value: $reminder.amount, in: 1...365)
                    Picker("Unit", selection: $reminder.unit) { ForEach(ReminderUnit.allCases) { Text($0.title).tag($0) } }
                        .onChange(of: reminder.unit) { showExactTime = $0.rawValue >= ReminderUnit.days.rawValue }
                    if showExactTime {
                        Stepper("Hour \(reminder.hour ?? 9)", value: Binding(get: { reminder.hour ?? 9 }, set: { reminder.hour = $0 }), in: 0...23)
                        Stepper("Minute \(reminder.min ?? 0)", value: Binding(get: { reminder.min ?? 0 }, set: { reminder.min = $0 }), in: 0...59)
                    }
                }
                Section("Rules") {
                    ForEach($reminder.rules) { $rule in RuleEditor(rule: $rule) }
                    if reminder.rules.count < 8 { Button("Add Rule") { reminder.rules.append(EventReminderRule()) } }
                }
                if state.reminders.reminders.contains(where: { $0.id == reminder.id }) {
                    Section { Button("Delete Reminder", role: .destructive) { state.reminders.remove(reminder); dismiss() } }
                }
            }
            .navigationTitle(reminder.title == nil ? "New Reminder" : "Edit Reminder")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { reminder.title = title.trimmingCharacters(in: .whitespacesAndNewlines); reminder.hour = showExactTime ? (reminder.hour ?? 9) : nil; reminder.min = showExactTime ? (reminder.min ?? 0) : nil; state.reminders.save(reminder); dismiss() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
        }
    }
}

struct RuleEditor: View {
    @Binding var rule: EventReminderRule
    var body: some View {
        Picker("Subject", selection: $rule.subject) { ForEach(ReminderRuleSubject.allCases) { Text($0.title).tag($0) } }
        Picker("Match", selection: $rule.action) { ForEach(ReminderRuleAction.allCases) { Text($0.title).tag($0) } }
        TextField("Pattern", text: $rule.pattern)
        Picker("Next rule", selection: Binding(get: { rule.relationWithNext ?? .and }, set: { rule.relationWithNext = $0 })) { ForEach(ReminderRuleRelation.allCases) { Text($0.title).tag($0) } }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var state: PokfuAppState
    @Environment(\.openURL) private var openURL
    @State private var showAbout = false
    @State private var showAccount = false

    var body: some View {
        AdaptiveNavigation("Settings") {
            List {
                Section("ACCOUNT") {
                    Button { if state.moodle.isLoggedIn { showAccount = true } else { state.moodle.startAuthentication() } } label: { Label { VStack(alignment: .leading) { Text(state.moodle.isLoggedIn ? "Moodle Account" : "Connect to Moodle"); Text(state.moodle.isLoggedIn ? (state.moodle.siteInfo?.username ?? "") : "Sync your courses and deadlines").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "person.crop.circle") } }
                }
                Section("PREFERENCES") {
                    NavigationLink("General") { GeneralSettingsView() }
                    NavigationLink {
                        AIProvidersView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Providers")
                                Text(state.ai.activeProviderName ?? "Apple Intelligence or Share Sheet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                    }
                    NavigationLink("Events") { EventSettingsView() }
                    NavigationLink("Reminders") { ReminderSettingsView() }
                    NavigationLink("Courses") { CourseSettingsView() }
                    NavigationLink("Calendar") { CalendarSettingsView() }
                    Button { showAbout = true } label: { Label("About", systemImage: "info.circle") }
                }
                if state.moodle.isLoggedIn { Section { Button("Sign Out", role: .destructive) { state.moodle.logout() } } }
            }
            .listStyle(.insetGrouped)
            .sheet(isPresented: $showAbout) { AboutView() }
            .sheet(isPresented: $showAccount) { AccountView() }
        }
    }
}

struct AIProvidersView: View {
    @EnvironmentObject private var state: PokfuAppState

    var body: some View {
        List {
            Section {
                if state.ai.configuredProviders.isEmpty {
                    Label("No cloud provider connected", systemImage: "icloud.slash")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Active provider", selection: Binding(
                        get: { state.ai.activeProvider?.rawValue ?? "" },
                        set: { raw in
                            state.ai.select(AIProviderKind(rawValue: raw))
                        }
                    )) {
                        Text("Apple Intelligence / Share Sheet").tag("")
                        ForEach(state.ai.configuredProviders) { provider in
                            Text(provider.name).tag(provider.rawValue)
                        }
                    }
                }
            } header: {
                Text("ACTIVE")
            } footer: {
                Text("The selected provider receives the prepared Moodle question and relevant course context. If no provider is selected, Pokfu uses Apple Intelligence when available or the system share sheet.")
            }

            Section("CONNECT A PROVIDER") {
                ForEach(AIProviderKind.allCases) { provider in
                    NavigationLink {
                        AIProviderEditorView(provider: provider)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: state.ai.isConfigured(provider) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(state.ai.isConfigured(provider) ? Color.pokfuBlue : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                Text(provider.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if state.ai.workingProvider == provider {
                                ProgressView()
                            }
                        }
                    }
                }
            }

            Section("IMPORTANT") {
                Text("API keys are stored in the iOS Keychain, not in the app's normal settings. Pokfu does not include a shared developer key. You are responsible for the provider's quota, billing, and data policies.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AI Providers")
    }
}

struct AIProviderEditorView: View {
    @EnvironmentObject private var state: PokfuAppState
    @Environment(\.dismiss) private var dismiss

    let provider: AIProviderKind
    @State private var endpoint: String
    @State private var model: String
    @State private var apiKey = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var didLoad = false

    init(provider: AIProviderKind) {
        self.provider = provider
        _endpoint = State(initialValue: provider.defaultEndpoint)
        _model = State(initialValue: provider.defaultModel)
    }

    var body: some View {
        Form {
            Section {
                Text(provider.setupHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Open provider setup guide", destination: provider.documentationURL)
            } header: {
                Text(provider.name)
            }

            Section("CONNECTION") {
                TextField("API base URL", text: $endpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                TextField("Model name", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                SecureField(state.ai.isConfigured(provider) ? "API key (leave blank to keep current)" : "API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }

            Section {
                Button("Save connection") {
                    save()
                }
                if state.ai.isConfigured(provider) {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("Test connection")
                            Spacer()
                            if state.ai.workingProvider == provider { ProgressView() }
                        }
                    }
                    .disabled(state.ai.workingProvider != nil)
                    Button("Remove connection", role: .destructive) {
                        state.ai.disconnect(provider)
                        apiKey = ""
                        statusMessage = "Connection removed."
                    }
                }
            }

            if let statusMessage {
                Section { Label(statusMessage, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            }

            Section("PRIVACY") {
                Text("Pokfu sends the question, ranked Moodle search results, and extracted text from selected course files to this provider when you ask the tutor. Moodle passwords and Moodle API tokens are never sent to the AI provider.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle(provider.name)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            let configuration = state.ai.configuration(for: provider)
            endpoint = configuration.endpoint
            model = configuration.model
            apiKey = state.ai.apiKey(for: provider) ?? ""
        }
    }

    private func save() {
        do {
            let key = apiKey.isEmpty ? (state.ai.apiKey(for: provider) ?? "") : apiKey
            try state.ai.save(provider: provider, endpoint: endpoint, model: model, apiKey: key)
            statusMessage = "Saved. \(provider.name) is ready for Moodle Tutor."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func test() async {
        do {
            try await state.ai.test(provider: provider)
            statusMessage = "Connection successful."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var state: PokfuAppState
    var body: some View {
        Form {
            Picker("Default Tab", selection: Binding(get: { state.settings.int(SettingKey.defaultTab) }, set: { state.settings.set(SettingKey.defaultTab, $0) })) { Text("Events").tag(0); Text("Courses").tag(1); Text("Calendar").tag(2) }
            Picker("App Theme", selection: Binding(get: { state.settings.int(SettingKey.themeMode) }, set: { state.settings.set(SettingKey.themeMode, $0) })) { Text("Follow System").tag(0); Text("Light").tag(1); Text("Dark").tag(2) }
            Button("Clear Cache") { state.moodle.clearCourseCache() }
        }
        .navigationTitle("General")
    }
}

struct EventSettingsView: View {
    @EnvironmentObject private var state: PokfuAppState
    var body: some View {
        Form {
            Picker("Deadline Display", selection: Binding(get: { state.settings.int(SettingKey.deadlineDisplay) }, set: { state.settings.set(SettingKey.deadlineDisplay, $0) })) { Text("Date Only").tag(0); Text("Date + Time").tag(1); Text("Days Left").tag(2); Text("Detailed").tag(3) }
            Toggle("Sync Completion Status", isOn: Binding(get: { state.settings.bool(SettingKey.syncCompletion, default: true) }, set: { state.settings.set(SettingKey.syncCompletion, $0) }))
            Toggle("Show Progress Indicator", isOn: Binding(get: { state.settings.bool(SettingKey.showProgress, default: true) }, set: { state.settings.set(SettingKey.showProgress, $0) }))
            Toggle("Grey Out Completed Events", isOn: Binding(get: { state.settings.bool(SettingKey.greyOutCompleted, default: true) }, set: { state.settings.set(SettingKey.greyOutCompleted, $0) }))
            Toggle("Differentiate Custom Events", isOn: Binding(get: { state.settings.bool(SettingKey.differentiateCustom, default: true) }, set: { state.settings.set(SettingKey.differentiateCustom, $0) }))
            if #available(iOS 16.1, *) { Toggle("Pin Events Automatically", isOn: Binding(get: { state.settings.bool(SettingKey.autoPinEvent) }, set: { state.settings.set(SettingKey.autoPinEvent, $0) })) }
        }
        .navigationTitle("Events")
    }
}

struct ReminderSettingsView: View {
    @EnvironmentObject private var state: PokfuAppState
    var body: some View {
        Form {
            Toggle("Ignore Completed Events", isOn: Binding(get: { state.settings.bool(SettingKey.ignoreCompleted, default: true) }, set: { state.settings.set(SettingKey.ignoreCompleted, $0); state.reminders.rescheduleAll() }))
            Toggle("Ignore Custom Events", isOn: Binding(get: { state.settings.bool(SettingKey.ignoreCustom) }, set: { state.settings.set(SettingKey.ignoreCustom, $0); state.reminders.rescheduleAll() }))
        }
        .navigationTitle("Reminders")
    }
}

struct CourseSettingsView: View {
    @EnvironmentObject private var state: PokfuAppState
    var body: some View {
        Form {
            Toggle("Only Display Resources", isOn: Binding(get: { state.settings.bool(SettingKey.onlyShowResources, default: true) }, set: { state.settings.set(SettingKey.onlyShowResources, $0) }))
            Toggle("Open Resource Modules in Browser", isOn: Binding(get: { state.settings.bool(SettingKey.openResourceInBrowser) }, set: { state.settings.set(SettingKey.openResourceInBrowser, $0) }))
        }
        .navigationTitle("Courses")
    }
}

struct CalendarSettingsView: View {
    @EnvironmentObject private var state: PokfuAppState
    var body: some View {
        Form { Toggle("Show Workload Indicator", isOn: Binding(get: { state.settings.bool(SettingKey.showWorkload, default: true) }, set: { state.settings.set(SettingKey.showWorkload, $0) })) }.navigationTitle("Calendar")
    }
}

struct AccountView: View {
    var body: some View { VStack(spacing: 24) { Image(systemName: "checkmark.seal.fill").font(.system(size: 72)).foregroundStyle(Color.pokfuBlue); Text("Pokfu is connected to Moodle.").font(.title2.weight(.bold)); Text("Pokfu uses Moodle’s supported service APIs and does not save browser cookies.").multilineTextAlignment(.center).foregroundStyle(.secondary) }.padding().navigationTitle("Moodle Account") }
}

private struct PokfuAppIconView: View {
    private static let appIcon = [
        "AppIcon60x60", "AppIcon76x76", "AppIcon1024x1024", "AppIcon"
    ].compactMap { UIImage(named: $0) }.first

    var body: some View {
        Group {
            if let appIcon = Self.appIcon {
                Image(uiImage: appIcon)
                    .resizable()
                    .scaledToFit()
            } else {
                // The launch artwork is the same Pokfu mark and is a safer
                // fallback than showing an unrelated SF Symbol.
                Image("LaunchImage")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        .accessibilityLabel("Pokfu app icon")
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        PokfuAppIconView()
                        Text("Pokfu").font(.largeTitle.weight(.bold))
                        Text("A focused Moodle companion for deadlines, courses, reminders, and calendar planning.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                }
                Section("CONTACT") {
                    Link(destination: PokfuBrand.contactURL) {
                        Label("Email Support", systemImage: "envelope")
                    }
                    Text(PokfuBrand.contactEmail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Link("Source Project", destination: PokfuBrand.upstreamURL)
                    Link("Privacy Policy", destination: PokfuBrand.privacyURL)
                }
            }
            .navigationTitle("About")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct CrossedOffText: View {
    let text: String
    let isCrossedOff: Bool
    let font: Font
    let color: Color

    private var renderedText: AttributedString {
        var value = AttributedString(text)
        if isCrossedOff { value.strikethroughStyle = .single }
        return value
    }

    var body: some View {
        Text(renderedText)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HTMLContentView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> UITextView {
        // Moodle summaries often contain HTML attributes that TextKit 2 does
        // not support. Build the text view with an explicit TextKit 1 stack so
        // UIKit does not switch modes during a SwiftUI update.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: .zero)
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let view = UITextView(frame: .zero, textContainer: textContainer)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byCharWrapping
        view.adjustsFontForContentSizeCategory = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let wrappedHTML = """
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        html, body { margin: 0; padding: 0; max-width: 100%; overflow-wrap: anywhere; word-break: break-word; }
        img, video, iframe { max-width: 100%; height: auto; }
        table { max-width: 100%; width: 100%; table-layout: fixed; }
        td, th { overflow-wrap: anywhere; word-break: break-word; }
        pre, code { white-space: pre-wrap; overflow-wrap: anywhere; word-break: break-word; }
        </style>
        \(html)
        """
        guard let data = wrappedHTML.data(using: .utf8), let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) else {
            view.text = html
            view.font = UIFont.preferredFont(forTextStyle: .body)
            view.invalidateIntrinsicContentSize()
            return
        }
        view.attributedText = attributed
        view.textColor = UIColor.label
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.textContainer.lineBreakMode = .byCharWrapping
        view.invalidateIntrinsicContentSize()
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        uiView.bounds.size.width = width
        let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fittingSize.height))
    }
}

extension URL {
    var queryItems: [String: String] {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?.reduce(into: [:]) { $0[$1.name] = $1.value } ?? [:]
    }
    subscript(query key: String) -> String? { queryItems[key] }
}

extension Color {
    static let pokfuBlue = Color(red: 79 / 255, green: 70 / 255, blue: 229 / 255)
}
