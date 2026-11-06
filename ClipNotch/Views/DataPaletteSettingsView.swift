import SwiftUI

struct DataPaletteSettingsView: View {
    @Bindable var store: DataPaletteStore
    @State private var editingProfile: DataPaletteProfile?
    @State private var deletingProfile: DataPaletteProfile?
    @State private var editingType: DataPaletteType?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(ClipNotchTypography.callout).foregroundStyle(.red)
            }
            if !store.isLoaded {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(store.isLoading ? "Loading your profiles…" : "Your profiles could not be loaded.")
                        Button("Load Data Palette") { Task { await store.load() } }.disabled(store.isLoading)
                    }
                }
            } else {
                HStack {
                    Text("Profiles").font(ClipNotchTypography.heading)
                    Spacer()
                    Button("Add Profile", systemImage: "plus") { editingProfile = DataPaletteProfile(name: "") }
                        .buttonStyle(ClipNotchButtonStyle(.primary)).disabled(store.isSaving)
                }
                if store.profiles.isEmpty {
                    SettingsCard {
                        HStack(spacing: 16) {
                            Image("OnboardingProfiles").resizable().scaledToFit().frame(width: 86, height: 76).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("A little less repeat typing.").font(ClipNotchTypography.label)
                                Text("Add a profile to save the details you use in forms.")
                                    .font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
                            }
                        }
                    }
                }
                ForEach(store.profiles) { profile in
                    SettingsCard {
                        HStack(spacing: 14) {
                            AccentIcon(symbol: "person.crop.rectangle")
                            VStack(alignment: .leading, spacing: 5) {
                                Text(profile.name).font(ClipNotchTypography.heading).lineLimit(1).help(profile.name)
                                Text(profile.filledFields.count == 1 ? "1 saved value" : "\(profile.filledFields.count) saved values")
                                    .font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
                            }
                            Spacer()
                            Button("Edit") { editingProfile = profile }
                                .accessibilityLabel("Edit \(profile.name)")
                            Button(role: .destructive) { deletingProfile = profile } label: { Image(systemName: "trash") }
                                .buttonStyle(ClipNotchButtonStyle(.quiet))
                                .accessibilityLabel("Delete \(profile.name)")
                        }
                    }
                }
                Label("Stored on this Mac. Separate from clipboard history limits.", systemImage: "lock.shield")
                    .font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Category synonyms").font(ClipNotchTypography.heading)
                    Text("Help ClipNotch recognise different labels for the same detail. Applies to every profile.")
                        .font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
                }
                .padding(.top, 8)
                SettingsCard {
                    VStack(spacing: 0) {
                        if store.allDataTypes.isEmpty {
                            Text("Add a field to a profile to set up its synonyms.")
                                .font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
                        }
                        ForEach(Array(store.allDataTypes.enumerated()), id: \.element.id) { index, type in
                            if index > 0 { Divider() }
                            HStack(spacing: 10) {
                                Image(systemName: "text.alignleft").foregroundStyle(ClipNotchDesign.secondaryLabel).accessibilityHidden(true)
                                Text(type.label).font(ClipNotchTypography.label).lineLimit(1).help(type.label)
                                Spacer()
                                Button("Edit synonyms") { editingType = type }
                                    .buttonStyle(ClipNotchButtonStyle(.quiet))
                                    .foregroundStyle(ClipNotchDesign.accent)
                                    .accessibilityLabel("Edit \(type.label) synonyms")
                            }.padding(.vertical, 10)
                        }
                    }
                }
            }
        }
        .buttonStyle(ClipNotchButtonStyle())
        .task { await store.load() }
        .font(ClipNotchTypography.body)
        .sheet(item: $editingProfile) { profile in
            DataPaletteProfileEditor(profile: profile, store: store)
        }
        .sheet(item: $editingType) { type in
            CategorySynonymEditor(type: type, store: store, text: (store.synonyms[type.id] ?? []).joined(separator: "\n"))
        }
        .sheet(item: $deletingProfile) { profile in
            VStack(alignment: .leading, spacing: 20) {
                Label("Delete \(profile.name)?", systemImage: "trash")
                    .font(ClipNotchTypography.title)
                Text("This removes the profile and all its saved fields.")
                    .foregroundStyle(ClipNotchDesign.secondaryLabel)
                if let error = store.errorMessage {
                    Text(error).font(ClipNotchTypography.callout).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { deletingProfile = nil }.keyboardShortcut(.cancelAction)
                    Button("Delete Profile", role: .destructive) {
                        Task { if await store.delete(profile) { deletingProfile = nil } }
                    }
                    .buttonStyle(ClipNotchButtonStyle(.primary))
                }
            }
            .padding(28).frame(width: 400)
            .buttonStyle(ClipNotchButtonStyle())
            .background(ClipNotchWindowSurface())
            .disabled(store.isSaving)
            .interactiveDismissDisabled(store.isSaving)
        }
    }
}

private struct CategorySynonymEditor: View {
    let type: DataPaletteType
    @Bindable var store: DataPaletteStore
    @State var text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AccentIcon(symbol: "text.alignleft")
                Text("\(type.label) synonyms").font(ClipNotchTypography.title)
            }
            Text("Add one form label per line. For example: Mobile number.")
                .font(ClipNotchTypography.body).foregroundStyle(ClipNotchDesign.secondaryLabel)
            TextEditor(text: $text).font(ClipNotchTypography.body).frame(height: 140)
                .scrollContentBackground(.hidden).padding(10)
                .background(ClipNotchDesign.controlBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ClipNotchDesign.separator))
                .accessibilityLabel("Synonyms for \(type.label)")
            if let builtIn = AutofillCategory.builtInSynonyms[type.id] {
                Text("Built-in: \(builtIn.joined(separator: ", "))")
                    .font(ClipNotchTypography.caption).foregroundStyle(ClipNotchDesign.secondaryLabel)
            }
            if let error = store.errorMessage { Text(error).font(ClipNotchTypography.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        if await store.saveSynonyms(text.components(separatedBy: .newlines), for: type) { dismiss() }
                    }
                }.keyboardShortcut(.defaultAction).buttonStyle(ClipNotchButtonStyle(.primary))
            }
        }
        .font(ClipNotchTypography.body)
        .padding(24).frame(width: 460)
        .buttonStyle(ClipNotchButtonStyle())
        .background(ClipNotchWindowSurface())
        .disabled(store.isSaving).interactiveDismissDisabled(store.isSaving)
    }
}

struct DataPaletteProfileEditor: View {
    @State var profile: DataPaletteProfile
    @Bindable var store: DataPaletteStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                AccentIcon(symbol: "person.crop.rectangle")
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.profiles.contains(where: { $0.id == profile.id }) ? "Edit Profile" : "New Profile")
                        .font(ClipNotchTypography.title)
                    Text("Keep the details you use again and again.")
                        .font(ClipNotchTypography.callout).foregroundStyle(ClipNotchDesign.secondaryLabel)
                }
            }
            Text("Profile name").font(ClipNotchTypography.label)
            TextField("For example, Personal or College", text: $profile.name)
                .textFieldStyle(ClipNotchTextFieldStyle())
                .accessibilityLabel("Profile name")
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($profile.fields) { $field in
                        SettingsCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    TextField("Field label", text: $field.label)
                                        .textFieldStyle(ClipNotchTextFieldStyle())
                                        .accessibilityLabel("Field label")
                                    Button(role: .destructive) {
                                        profile.fields.removeAll { $0.id == field.id }
                                    } label: { Image(systemName: "minus") }
                                    .buttonStyle(ClipNotchButtonStyle(.icon))
                                    .accessibilityLabel("Remove \(field.label) field")
                                }
                                TextEditor(text: $field.value)
                                    .font(ClipNotchTypography.body)
                                    .frame(height: 56)
                                    .scrollContentBackground(.hidden)
                                    .padding(6)
                                    .background(ClipNotchDesign.windowBackground, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ClipNotchDesign.separator))
                                    .accessibilityLabel("\(field.label) value")
                            }
                        }
                    }
                }
                .padding(2)
                .padding(.trailing, 4)
            }
            Button("Add Field", systemImage: "plus") {
                profile.fields.append(DataPaletteField(label: ""))
            }
            if let error = store.errorMessage {
                Text(error).font(ClipNotchTypography.caption).foregroundStyle(.red)
            }
            HStack {
                Text("Profile names and field labels cannot be empty.")
                    .font(ClipNotchTypography.caption).foregroundStyle(ClipNotchDesign.secondaryLabel)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task { if await store.save(profile) { dismiss() } }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(ClipNotchButtonStyle(.primary))
                .disabled(!profile.isValid || store.isSaving)
            }
        }
        .padding(24)
        .font(ClipNotchTypography.body)
        .frame(width: 540, height: 530)
        .buttonStyle(ClipNotchButtonStyle())
        .background(ClipNotchWindowSurface())
        .disabled(store.isSaving)
        .interactiveDismissDisabled(store.isSaving)
    }
}
