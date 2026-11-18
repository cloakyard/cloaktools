import Foundation

public enum QRContentKind: String, CaseIterable, Identifiable, Sendable {
    case text = "Text", link = "Web link", contact = "Contact card (vCard)", wifi = "Wi-Fi network"
    case email = "Email", phone = "Phone call", sms = "Text message", location = "Map location", event = "Calendar event"
    public var id: Self { self }

    public static func recognizing(_ value: String) -> Self {
        let prefix = value.prefix(40).uppercased()
        if prefix.hasPrefix("WIFI:") { return .wifi }
        if prefix.hasPrefix("BEGIN:VCARD") { return .contact }
        if prefix.hasPrefix("BEGIN:VCALENDAR") || prefix.hasPrefix("BEGIN:VEVENT") { return .event }
        if prefix.hasPrefix("HTTP://") || prefix.hasPrefix("HTTPS://") { return .link }
        if prefix.hasPrefix("MAILTO:") { return .email }
        if prefix.hasPrefix("TEL:") { return .phone }
        if prefix.hasPrefix("SMS:") || prefix.hasPrefix("SMSTO:") { return .sms }
        if prefix.hasPrefix("GEO:") { return .location }
        return .text
    }
}

public enum QRWiFiSecurity: String, CaseIterable, Identifiable, Sendable {
    case personal = "WPA", wep = "WEP", open = "nopass"
    public var id: Self { self }
    public var title: String {
        switch self { case .personal: "WPA / WPA2 Personal"; case .wep: "WEP"; case .open: "Open network" }
    }
}

private struct QRFieldError: LocalizedError {
    let errorDescription: String?
    init(_ description: String) { errorDescription = description }
}

/// Values come only from the active form. The PNG generator also accepts literal text directly.
public enum QRContent: Sendable {
    case text(String)
    case link(String)
    case contact(given: String, family: String, organization: String, phone: String, email: String, website: String)
    case wifi(ssid: String, security: QRWiFiSecurity, password: String, hidden: Bool)
    case email(recipient: String, subject: String, body: String)
    case phone(String)
    case sms(number: String, body: String)
    case location(latitude: String, longitude: String)
    case event(title: String, start: Date, end: Date, location: String)

    public func encoded(eventID: UUID = UUID(), createdAt: Date = Date()) throws -> String {
        let value: String
        switch self {
        case let .text(text): value = text
        case let .link(link): value = try Self.webLink(link)
        case let .contact(given, family, organization, phone, email, website):
            let first = try Self.line(given), last = try Self.line(family)
            guard !first.isEmpty || !last.isEmpty else { throw QRFieldError("Enter a first or last name.") }
            let fullName = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            var lines = ["BEGIN:VCARD", "VERSION:3.0", "N:\(Self.escape(last));\(Self.escape(first));;;", "FN:\(Self.escape(fullName))"]
            let company = try Self.line(organization), telephone = try Self.line(phone)
            if !company.isEmpty { lines.append("ORG:" + Self.escape(company)) }
            if !telephone.isEmpty { lines.append("TEL:" + Self.escape(telephone)) }
            if !email.isEmpty { lines.append("EMAIL;TYPE=INTERNET:" + (try Self.mailbox(email))) }
            if !website.isEmpty { lines.append("URL:" + (try Self.webLink(website))) }
            value = Self.document(lines + ["END:VCARD"])
        case let .wifi(ssid, security, password, hidden):
            guard (1...32).contains(ssid.utf8.count), !ssid.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw QRFieldError("Enter a network name of 1–32 bytes.")
            }
            var fields = ["T:" + security.rawValue, "S:" + Self.wifiEscape(ssid)]
            if security != .open {
                guard !password.isEmpty else { throw QRFieldError("Enter the network password.") }
                try Self.checkLength(password)
                guard !password.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                    throw QRFieldError("Use a password without control characters.")
                }
                fields.append("P:" + Self.wifiEscape(password))
            }
            if hidden { fields.append("H:true") }
            value = "WIFI:" + fields.joined(separator: ";") + ";;"
        case let .email(recipient, subject, body):
            let address = try Self.mailbox(recipient).split(separator: "@").map { Self.component(String($0)) }.joined(separator: "@")
            var headers: [String] = []
            if !subject.isEmpty { headers.append("subject=" + Self.component(try Self.line(subject))) }
            if !body.isEmpty { headers.append("body=" + Self.component(try Self.message(body).replacingOccurrences(of: "\n", with: "\r\n"))) }
            value = "mailto:" + address + (headers.isEmpty ? "" : "?" + headers.joined(separator: "&"))
        case let .phone(number): value = "tel:" + (try Self.phoneNumber(number))
        case let .sms(number, body):
            let number = try Self.phoneNumber(number)
            value = "sms:" + number + (body.isEmpty ? "" : "?body=" + Self.component(try Self.message(body)))
        case let .location(latitude, longitude):
            let lat = try Self.coordinate(latitude, name: "latitude", limit: 90)
            let lon = try Self.coordinate(longitude, name: "longitude", limit: 180)
            value = "geo:" + lat + "," + lon
        case let .event(title, start, end, location):
            let title = try Self.line(title), place = try Self.line(location)
            guard !title.isEmpty else { throw QRFieldError("Enter the event title.") }
            guard floor(end.timeIntervalSince1970) > floor(start.timeIntervalSince1970) else { throw QRFieldError("Choose an end after the start.") }
            let utc = DateFormatter()
            utc.locale = Locale(identifier: "en_US_POSIX")
            utc.calendar = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0)
            utc.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Cloakyard//CloakTools//EN", "BEGIN:VEVENT",
                         "UID:\(eventID.uuidString)@cloaktools", "DTSTAMP:" + utc.string(from: createdAt),
                         "DTSTART:" + utc.string(from: start), "DTEND:" + utc.string(from: end), "SUMMARY:" + Self.escape(title)]
            if !place.isEmpty { lines.append("LOCATION:" + Self.escape(place)) }
            value = Self.document(lines + ["END:VEVENT", "END:VCALENDAR"])
        }
        try QRCodeCreation.validate(value)
        return value
    }

    private static func checkLength(_ value: String) throws {
        guard value.utf8.count <= QRCodeCreation.maximumInputBytes else { throw QRCodeError.inputTooLarge }
    }

    private static func line(_ value: String) throws -> String {
        try checkLength(value)
        guard !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw QRFieldError("Keep each field on one line.")
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private static func webLink(_ input: String) throws -> String {
        let link = try line(input)
        guard !link.contains(where: \.isWhitespace), let parts = URLComponents(string: link),
              ["https", "http"].contains(parts.scheme?.lowercased()), let host = parts.host, !host.isEmpty,
              let url = parts.url else { throw QRFieldError("Enter a full web address beginning with https:// or http://.") }
        return url.absoluteString
    }

    private static func mailbox(_ input: String) throws -> String {
        let mailbox = try line(input)
        let parts = mailbox.components(separatedBy: "@")
        let atom = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!#$%&'*+-/=?^_\u{60}{|}~")
        guard parts.count == 2, !parts[0].isEmpty, !parts[0].hasPrefix("."), !parts[0].hasSuffix("."), !parts[0].contains(".."),
              parts[0].unicodeScalars.allSatisfy(atom.contains),
              !parts[1].isEmpty, parts[1].components(separatedBy: ".").allSatisfy({ label in
                  !label.isEmpty && !label.hasPrefix("-") && !label.hasSuffix("-") && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
              }) else { throw QRFieldError("Enter one email address, such as name@example.com.") }
        return mailbox
    }

    private static func phoneNumber(_ input: String) throws -> String {
        let compact = try line(input).filter { !" ()-.".contains($0) }
        let digits = compact.dropFirst()
        guard compact.first == "+", (1...15).contains(digits.count), digits.first != "0",
              digits.utf8.allSatisfy({ (48...57).contains($0) }) else { throw QRFieldError("Include the country code, for example +1 202 555 0148.") }
        return compact
    }

    private static func message(_ input: String) throws -> String {
        try checkLength(input)
        guard !input.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && ![9, 10, 13].contains($0.value) }) else {
            throw QRCodeError.unsupportedControl
        }
        return input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private static func component(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)!
    }

    private static func coordinate(_ input: String, name: String, limit: Int) throws -> String {
        let text = try line(input)
        let hint = QRFieldError("Enter \(name) between −\(limit) and \(limit), using a decimal point.")
        guard text.wholeMatch(of: #/-?[0-9]+(?:\.[0-9]+)?/#) != nil else { throw hint }
        let magnitude = text.drop(while: { $0 == "-" }).split(separator: ".")
        let integer = magnitude[0].drop(while: { $0 == "0" })
        let fraction = magnitude.count == 2 ? magnitude[1] : ""
        guard let degrees = Int(integer.isEmpty ? "0" : String(integer)),
              degrees < limit || (degrees == limit && fraction.allSatisfy({ $0 == "0" })) else { throw hint }
        return (text.hasPrefix("-") ? "-" : "") + String(degrees) + (fraction.isEmpty ? "" : "." + fraction)
    }

    private static func wifiEscape(_ text: String) -> String {
        var output = ""
        for scalar in text.unicodeScalars {
            if "\\;,:\"".unicodeScalars.contains(scalar) { output += "\\" }
            output.unicodeScalars.append(scalar)
        }
        return output
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: ",", with: "\\,")
    }

    /// Fold content lines at 75 octets without splitting a UTF-8 scalar.
    private static func document(_ lines: [String]) -> String {
        var result = ""
        for line in lines {
            var bytes = 0
            for scalar in line.unicodeScalars {
                if bytes + scalar.utf8.count > 75 { result += "\r\n "; bytes = 1 }
                result.unicodeScalars.append(scalar)
                bytes += scalar.utf8.count
            }
            result += "\r\n"
        }
        return result
    }
}
