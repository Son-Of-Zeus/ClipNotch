import SwiftUI

struct DataPaletteSettingsView: View {
    @Bindable var store: DataPaletteStore
    @State private var editingProfile: DataPaletteProfile?
    @State private var deletingProfile: DataPaletteProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if !store.isLoaded {
                Button("Load Data Palette") { Task { await store.load() } }
            } else {
                if store.profiles.isEmpty {
                    Text("Add a profile to save values you use in forms.")
                        .font(.subheadline)
                        .foregroundStyle(ClipNotchDesign.secondaryLabel)
                }
                ForEach(store.profiles) { profile in
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.rectangle")
                            .foregroundStyle(ClipNotchDesign.secondaryLabel)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.name).font(.subheadline.weight(.medium))
                            Text("\(profile.filledFields.count) saved values")
                                .font(.caption).foregroundStyle(ClipNotchDesign.secondaryLabel)
                        }
                        Spacer()
                        Button("Edit") { editingProfile = profile }
                        Button(role: .destructive) { deletingProfile = profile } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete \(profile.name)")
                    }
                    Divider()
                }
                Button("Add Profile", systemImage: "plus") {
                    editingProfile = DataPaletteProfile(name: "")
                }
                .disabled(store.isSaving)
                Text("Values stay on this Mac. Clipboard history limits do not affect them.")
                    .font(.caption).foregroundStyle(ClipNotchDesign.secondaryLabel)
            }
        }
        .task { await store.load() }
        .sheet(item: $editingProfile) { profile in
            DataPaletteProfileEditor(profile: profile, store: store)
        }
        .confirmationDialog(
            "Delete \(deletingProfile?.name ?? "profile")?",
            isPresented: Binding(get: { deletingProfile != nil }, set: { if !$0 { deletingProfile = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Profile", role: .destructive) {
                if let profile = deletingProfile {
                    Task { _ = await store.delete(profile) }
                }
                deletingProfile = nil
            }
        } message: {
            Text("This removes the profile and all its saved fields.")
        }
    }
}

private struct DataPaletteProfileEditor: View {
    @State var profile: DataPaletteProfile
    @Bindable var store: DataPaletteStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Profile").font(.title2.weight(.semibold))
            TextField("Profile name", text: $profile.name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Profile name")
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($profile.fields) { $field in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Field label", text: $field.label)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Field label")
                                Button(role: .destructive) {
                                    profile.fields.removeAll { $0.id == field.id }
                                } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(field.label) field")
                            }
                            TextEditor(text: $field.value)
                                .font(.body)
                                .frame(height: 56)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(ClipNotchDesign.separator))
                                .accessibilityLabel("\(field.label) value")
                        }
                    }
                }
                .padding(2)
            }
            Button("Add Field", systemImage: "plus") {
                profile.fields.append(DataPaletteField(label: ""))
            }
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Text("Profile names and field labels cannot be empty.")
                    .font(.caption).foregroundStyle(ClipNotchDesign.secondaryLabel)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task { if await store.save(profile) { dismiss() } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!profile.isValid || store.isSaving)
            }
        }
        .padding(24)
        .frame(width: 510, height: 460)
        .disabled(store.isSaving)
        .interactiveDismissDisabled(store.isSaving)
    }
}
