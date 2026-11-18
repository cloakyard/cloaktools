import SwiftUI
import CloakToolsCore

extension QRContentKind {
    var defaultFilename: String {
        switch self {
        case .text: "QR code"
        case .contact: "Contact card"
        default: rawValue
        }
    }
}

/// Switching types in the same review keeps that type's inputs until the review closes.
struct QRContentDraft {
    var kind = QRContentKind.text
    var text = "", link = ""
    var given = "", family = "", organization = "", contactPhone = "", contactEmail = "", website = ""
    var ssid = "", password = ""
    var security = QRWiFiSecurity.personal
    var hidden = false
    var recipient = "", subject = "", emailBody = ""
    var phone = "", smsNumber = "", smsBody = ""
    var latitude = "", longitude = ""
    var eventTitle = "", place = ""
    var start: Date
    var end: Date

    init(now: Date = .now) {
        start = Calendar.current.dateInterval(of: .hour, for: now)?.end ?? now
        end = start.addingTimeInterval(3600)
    }

    func describesSameEvent(as other: Self) -> Bool {
        start == other.start && end == other.end && eventTitle.utf8.elementsEqual(other.eventTitle.utf8) && place.utf8.elementsEqual(other.place.utf8)
    }

    var content: QRContent {
        switch kind {
        case .text: .text(text)
        case .link: .link(link)
        case .contact: .contact(given: given, family: family, organization: organization, phone: contactPhone, email: contactEmail, website: website)
        case .wifi: .wifi(ssid: ssid, security: security, password: password, hidden: hidden)
        case .email: .email(recipient: recipient, subject: subject, body: emailBody)
        case .phone: .phone(phone)
        case .sms: .sms(number: smsNumber, body: smsBody)
        case .location: .location(latitude: latitude, longitude: longitude)
        case .event: .event(title: eventTitle, start: start, end: end, location: place)
        }
    }
}

struct QRContentForm: View {
    @Bindable var operation: QRCodeOperation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch operation.draft.kind {
            case .text:
                HStack {
                    Text("Text").font(.callout.weight(.medium))
                    Spacer()
                    Button(operation.draft.text.isEmpty ? "Try Example" : "Clear") {
                        operation.draft.text = operation.draft.text.isEmpty ? "https://example.com/" : ""
                    }.buttonStyle(.link)
                }
                editor($operation.draft.text, label: "QR text", height: 130)
            case .link:
                field("Web address", "https://example.com", $operation.draft.link)
            case .contact:
                field("First name", "Given name", $operation.draft.given)
                field("Last name", "Family name", $operation.draft.family)
                field("Phone", "Optional", $operation.draft.contactPhone)
                field("Email", "Optional", $operation.draft.contactEmail)
                field("Organization", "Optional", $operation.draft.organization)
                field("Website", "https://… (optional)", $operation.draft.website)
            case .wifi:
                field("Network name (SSID)", "Exact network name", $operation.draft.ssid)
                Picker("Security", selection: $operation.draft.security) {
                    ForEach(QRWiFiSecurity.allCases) { Text($0.title).tag($0) }
                }
                if operation.draft.security != .open {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password").font(.callout.weight(.medium))
                        SecureField("Network password", text: $operation.draft.password)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("Network password")
                    }
                }
                Toggle("Hidden network", isOn: $operation.draft.hidden)
            case .email:
                field("To", "name@example.com", $operation.draft.recipient)
                field("Subject", "Optional", $operation.draft.subject)
                message($operation.draft.emailBody)
            case .phone:
                field("Phone number", "+1 202 555 0148", $operation.draft.phone)
            case .sms:
                field("Recipient number", "+1 202 555 0148", $operation.draft.smsNumber)
                message($operation.draft.smsBody)
            case .location:
                field("Latitude", "e.g. 19.0760", $operation.draft.latitude)
                field("Longitude", "e.g. 72.8777", $operation.draft.longitude)
            case .event:
                field("Event title", "Event name", $operation.draft.eventTitle)
                DatePicker("Starts", selection: Binding(get: { operation.draft.start }, set: { start in
                    var draft = operation.draft
                    draft.end = start.addingTimeInterval(max(60, draft.end.timeIntervalSince(draft.start)))
                    draft.start = start
                    operation.draft = draft
                }))
                DatePicker("Ends", selection: $operation.draft.end)
                Text(TimeZone.current.identifier).font(.caption).foregroundStyle(.secondary)
                field("Location", "Optional", $operation.draft.place)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).autocorrectionDisabled()
    }

    private func field(_ title: String, _ prompt: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.medium))
            TextField(prompt, text: value).textFieldStyle(.roundedBorder).accessibilityLabel(title)
        }
    }

    private func message(_ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Message (optional)").font(.callout.weight(.medium))
            editor(value, label: "Message", height: 66)
        }
    }

    private func editor(_ value: Binding<String>, label: String, height: CGFloat) -> some View {
        PlainTextEditor(text: value, editable: !operation.busy, label: label, rejectLargeInput: operation.rejectLargeInput,
                        maximumInputBytes: QRCodeCreation.maximumInputBytes)
            .frame(height: height).background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 8))
            .clipShape(.rect(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator.opacity(0.6)))
    }
}
