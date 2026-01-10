import Foundation
import Contacts

final class ContactsServer: MCPServer {
    let id = "contacts"
    let name = "連絡先"
    let serverDescription = "連絡先の検索・閲覧を行います"
    let icon = "person.crop.circle"

    private let store = CNContactStore()

    func listTools() -> [MCPTool] {
        [
            MCPTool(
                name: "search_contacts",
                description: "連絡先を検索します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "query": MCPPropertySchema(type: "string", description: "検索キーワード（名前、会社名など）"),
                        "limit": MCPPropertySchema(type: "integer", description: "取得件数上限（デフォルト: 10）")
                    ],
                    required: ["query"]
                )
            ),
            MCPTool(
                name: "get_contact",
                description: "連絡先の詳細情報を取得します",
                inputSchema: MCPInputSchema(
                    properties: [
                        "contact_id": MCPPropertySchema(type: "string", description: "連絡先のID")
                    ],
                    required: ["contact_id"]
                )
            ),
            MCPTool(
                name: "list_groups",
                description: "連絡先グループ一覧を取得します",
                inputSchema: MCPInputSchema()
            ),
            MCPTool(
                name: "get_my_card",
                description: "自分の連絡先カードを取得します",
                inputSchema: MCPInputSchema()
            )
        ]
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPResult {
        try await requestAccess()

        switch name {
        case "search_contacts":
            return try await searchContacts(arguments: arguments)
        case "get_contact":
            return try await getContact(arguments: arguments)
        case "list_groups":
            return try await listGroups()
        case "get_my_card":
            return try await getMyCard()
        default:
            throw MCPClientError.toolNotFound(name)
        }
    }

    private func requestAccess() async throws {
        let status = CNContactStore.authorizationStatus(for: .contacts)

        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = try await store.requestAccess(for: .contacts)
            guard granted else {
                throw MCPClientError.permissionDenied("連絡先へのアクセスが拒否されました")
            }
        default:
            throw MCPClientError.permissionDenied("連絡先へのアクセス権限がありません")
        }
    }

    private func searchContacts(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let query = arguments["query"]?.stringValue else {
            throw MCPClientError.invalidArguments("query is required")
        }

        let limit = arguments["limit"]?.intValue ?? 10

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey,
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactOrganizationNameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey
        ] as [CNKeyDescriptor]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.predicate = CNContact.predicateForContacts(matchingName: query)

        var contacts: [CNContact] = []
        try store.enumerateContacts(with: request) { contact, stop in
            contacts.append(contact)
            if contacts.count >= limit {
                stop.pointee = true
            }
        }

        var result = "👥 検索結果: \"\(query)\"\n\n"

        if contacts.isEmpty {
            result += "該当する連絡先が見つかりませんでした"
        } else {
            for contact in contacts {
                result += formatContactSummary(contact)
            }
        }

        return MCPResult(content: [.text(result)])
    }

    private func getContact(arguments: [String: JSONValue]) async throws -> MCPResult {
        guard let contactId = arguments["contact_id"]?.stringValue else {
            throw MCPClientError.invalidArguments("contact_id is required")
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey,
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactMiddleNameKey,
            CNContactNicknameKey,
            CNContactOrganizationNameKey,
            CNContactDepartmentNameKey,
            CNContactJobTitleKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactPostalAddressesKey,
            CNContactUrlAddressesKey,
            CNContactBirthdayKey,
            CNContactNoteKey
        ] as [CNKeyDescriptor]

        let contact = try store.unifiedContact(withIdentifier: contactId, keysToFetch: keysToFetch)

        return MCPResult(content: [.text(formatContactDetail(contact))])
    }

    private func listGroups() async throws -> MCPResult {
        let groups = try store.groups(matching: nil)

        var result = "📁 連絡先グループ一覧\n\n"

        if groups.isEmpty {
            result += "グループがありません"
        } else {
            for group in groups {
                let predicate = CNContact.predicateForContactsInGroup(withIdentifier: group.identifier)
                let contacts = try store.unifiedContacts(
                    matching: predicate,
                    keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
                )
                result += "• \(group.name) (\(contacts.count)人)\n"
            }
        }

        return MCPResult(content: [.text(result)])
    }

    private func getMyCard() async throws -> MCPResult {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey,
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactOrganizationNameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey
        ] as [CNKeyDescriptor]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)

        var myCard: CNContact?
        try store.enumerateContacts(with: request) { contact, stop in
            myCard = contact
            stop.pointee = true
        }

        if let contact = myCard {
            return MCPResult(content: [.text(formatContactDetail(contact))])
        } else {
            return MCPResult(content: [.text("自分の連絡先カードが設定されていません")])
        }
    }

    private func formatContactSummary(_ contact: CNContact) -> String {
        var str = "👤 "
        str += "\(contact.familyName) \(contact.givenName)".trimmingCharacters(in: .whitespaces)

        if !contact.organizationName.isEmpty {
            str += " (\(contact.organizationName))"
        }

        if let phone = contact.phoneNumbers.first?.value.stringValue {
            str += "\n   📞 \(phone)"
        }

        if let email = contact.emailAddresses.first?.value as String? {
            str += "\n   ✉️ \(email)"
        }

        str += "\n   ID: \(contact.identifier)\n\n"
        return str
    }

    private func formatContactDetail(_ contact: CNContact) -> String {
        var str = "👤 連絡先詳細\n\n"

        let fullName = "\(contact.familyName) \(contact.givenName)".trimmingCharacters(in: .whitespaces)
        if !fullName.isEmpty {
            str += "名前: \(fullName)\n"
        }

        if !contact.organizationName.isEmpty {
            str += "会社: \(contact.organizationName)\n"
        }

        if !contact.jobTitle.isEmpty {
            str += "役職: \(contact.jobTitle)\n"
        }

        if !contact.phoneNumbers.isEmpty {
            str += "\n電話番号:\n"
            for phone in contact.phoneNumbers {
                let label = CNLabeledValue<NSString>.localizedString(forLabel: phone.label ?? "")
                str += "  \(label): \(phone.value.stringValue)\n"
            }
        }

        if !contact.emailAddresses.isEmpty {
            str += "\nメールアドレス:\n"
            for email in contact.emailAddresses {
                let label = CNLabeledValue<NSString>.localizedString(forLabel: email.label ?? "")
                str += "  \(label): \(email.value as String)\n"
            }
        }

        if let birthday = contact.birthday {
            let formatter = DateFormatter()
            formatter.dateFormat = "M月d日"
            if let date = birthday.date {
                str += "\n誕生日: \(formatter.string(from: date))\n"
            }
        }

        if !contact.note.isEmpty {
            str += "\nメモ: \(contact.note)\n"
        }

        return str
    }
}
