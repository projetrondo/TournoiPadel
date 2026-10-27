import PadelCore
import SwiftUI

/// Liste des joueurs enregistrés d'une session : ajout, modification, retrait.
struct SessionPlayersView: View {
    let session: PlaySession

    @Environment(SessionLibrary.self) private var sessions
    @State private var newName = ""
    @State private var editing: SessionMember?
    @State private var isShowingArchived = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("Prénom ou surnom", text: $newName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($isFieldFocused)
                    .onSubmit(add)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.accent)
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Ajouter le joueur")
            }

            let active = session.activeMembers
            if active.isEmpty {
                Text("Ajoutez les joueurs du groupe une seule fois : ils seront proposés à chaque nouveau tournoi.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .cardStyle()
            } else {
                membersCard(active)
            }

            let archived = session.members.filter(\.isArchived)
            if !archived.isEmpty {
                DisclosureGroup(isExpanded: $isShowingArchived) {
                    VStack(spacing: 0) {
                        ForEach(archived) { member in
                            HStack {
                                Text(member.name)
                                    .foregroundStyle(Theme.secondaryText)
                                Spacer()
                                Button("Réactiver") {
                                    sessions.perform {
                                        try sessions.modify(id: session.id) { try $0.addMember(name: member.name) }
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                            .padding(.vertical, 8)
                        }
                    }
                } label: {
                    Text("Joueurs retirés (\(archived.count))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .tint(Theme.secondaryText)
            }

            Text("Retirer un joueur ne supprime pas ses résultats : il reste dans les classements des périodes où il a joué.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .sheet(item: $editing) { member in
            EditMemberView(sessionID: session.id, member: member)
                .presentationDetents([.medium])
        }
    }

    private func membersCard(_ members: [SessionMember]) -> some View {
        VStack(spacing: 0) {
            ForEach(members) { member in
                if member.id != members.first?.id {
                    Divider().overlay(Theme.stroke).padding(.leading, 60)
                }
                HStack(spacing: 12) {
                    PlayerAvatar(name: member.name, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        if let level = member.level {
                            Text("Niveau \(level)")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Spacer()
                    Menu {
                        Button("Modifier", systemImage: "pencil") { editing = member }
                        Button("Retirer de la liste", systemImage: "person.fill.xmark", role: .destructive) {
                            sessions.perform { try sessions.modify(id: session.id) { $0.archiveMember(id: member.id) } }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(minWidth: 44, minHeight: 44)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityLabel("Options pour \(member.name)")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func add() {
        let name = newName
        sessions.perform {
            try sessions.modify(id: session.id) { try $0.addMember(name: name) }
            newName = ""
        }
        isFieldFocused = true
    }
}

/// Modification du nom et du niveau d'un joueur enregistré.
struct EditMemberView: View {
    let sessionID: PlaySession.ID
    let member: SessionMember

    @Environment(SessionLibrary.self) private var sessions
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var level: Int?

    init(sessionID: PlaySession.ID, member: SessionMember) {
        self.sessionID = sessionID
        self.member = member
        _name = State(initialValue: member.name)
        _level = State(initialValue: member.level)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("Prénom ou surnom", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    Picker("Niveau", selection: $level) {
                        Text("Non renseigné").tag(Int?.none)
                        ForEach(Array(Player.levelRange), id: \.self) { value in
                            Text("Niveau \(value)").tag(Int?.some(value))
                        }
                    }
                } footer: {
                    Text("Le niveau sert au premier tour Mexicano « selon le niveau ».")
                }
            }
            .eagleScreenBackground()
            .navigationTitle("Modifier le joueur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        sessions.perform {
                            try sessions.modify(id: sessionID) { try $0.updateMember(id: member.id, name: name, level: level) }
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
