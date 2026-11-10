import Foundation

// Ordered JSON value: the Windows host serializes in insertion order, so objects keep it too.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    public static func == (a: JSONValue, b: JSONValue) -> Bool {
        switch (a, b) {
        case (.null, .null): true
        case let (.bool(x), .bool(y)): x == y
        case let (.number(x), .number(y)): x == y
        case let (.string(x), .string(y)): x == y
        case let (.array(x), .array(y)): x == y
        case let (.object(x), .object(y)):
            x.count == y.count && zip(x, y).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: false
        }
    }

    public var objectPairs: [(key: String, value: JSONValue)]? {
        if case let .object(p) = self { p } else { nil }
    }

    public var stringValue: String? {
        if case let .string(s) = self { s } else { nil }
    }
}

public struct JSONError: Error, Equatable {
    public let message: String
}

// Output matches .NET JavaScriptSerializer: no whitespace, ' < > for ' < >.
extension JSONValue {
    public var serialized: String {
        var out = ""
        write(to: &out)
        return out
    }

    func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case let .bool(b): out += b ? "true" : "false"
        case let .number(n): out += Self.format(n)
        case let .string(s): Self.writeString(s, to: &out)
        case let .array(a):
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                v.write(to: &out)
            }
            out += "]"
        case let .object(p):
            out += "{"
            for (i, kv) in p.enumerated() {
                if i > 0 { out += "," }
                Self.writeString(kv.key, to: &out)
                out += ":"
                kv.value.write(to: &out)
            }
            out += "}"
        }
    }

    static func format(_ n: Double) -> String {
        if n == n.rounded(), abs(n) < 1e15 { return String(Int64(n)) }
        return "\(n)"
    }

    static func writeString(_ s: String, to out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "'", "<", ">", _ where u.value < 0x20:
                out += "\\u" + String(format: "%04x", u.value)
            default: out.unicodeScalars.append(u)
            }
        }
        out += "\""
    }
}

extension JSONValue {
    public static func parse(_ text: String) throws -> JSONValue {
        var p = Parser(Array(text.unicodeScalars))
        let v = try p.value()
        p.skipSpace()
        guard p.atEnd else { throw JSONError(message: "trailing characters") }
        return v
    }

    private struct Parser {
        let s: [Unicode.Scalar]
        var i = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }

        var atEnd: Bool { i >= s.count }

        mutating func skipSpace() {
            while i < s.count, s[i] == " " || s[i] == "\n" || s[i] == "\r" || s[i] == "\t" { i += 1 }
        }

        mutating func expect(_ c: Unicode.Scalar) throws {
            guard i < s.count, s[i] == c else { throw JSONError(message: "expected \(c) at \(i)") }
            i += 1
        }

        mutating func literal(_ word: String, _ v: JSONValue) throws -> JSONValue {
            for c in word.unicodeScalars { try expect(c) }
            return v
        }

        mutating func value() throws -> JSONValue {
            skipSpace()
            guard i < s.count else { throw JSONError(message: "unexpected end") }
            switch s[i] {
            case "{": return try object()
            case "[": return try array()
            case "\"": return .string(try string())
            case "t": return try literal("true", .bool(true))
            case "f": return try literal("false", .bool(false))
            case "n": return try literal("null", .null)
            default: return try number()
            }
        }

        mutating func object() throws -> JSONValue {
            try expect("{")
            var pairs: [(key: String, value: JSONValue)] = []
            skipSpace()
            if i < s.count, s[i] == "}" { i += 1; return .object(pairs) }
            while true {
                skipSpace()
                let k = try string()
                skipSpace()
                try expect(":")
                pairs.append((k, try value()))
                skipSpace()
                if i < s.count, s[i] == "," { i += 1; continue }
                try expect("}")
                return .object(pairs)
            }
        }

        mutating func array() throws -> JSONValue {
            try expect("[")
            var items: [JSONValue] = []
            skipSpace()
            if i < s.count, s[i] == "]" { i += 1; return .array(items) }
            while true {
                items.append(try value())
                skipSpace()
                if i < s.count, s[i] == "," { i += 1; continue }
                try expect("]")
                return .array(items)
            }
        }

        mutating func string() throws -> String {
            try expect("\"")
            var out = String.UnicodeScalarView()
            while i < s.count {
                let c = s[i]
                i += 1
                if c == "\"" { return String(out) }
                guard c == "\\" else { out.append(c); continue }
                guard i < s.count else { break }
                let e = s[i]
                i += 1
                switch e {
                case "n": out.append("\n")
                case "r": out.append("\r")
                case "t": out.append("\t")
                case "b": out.append("\u{08}")
                case "f": out.append("\u{0C}")
                case "u": out.append(try unicodeEscape())
                default: out.append(e)
                }
            }
            throw JSONError(message: "unterminated string")
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= s.count, let v = UInt32(String(String.UnicodeScalarView(s[i..<i + 4])), radix: 16) else {
                throw JSONError(message: "bad \\u escape")
            }
            i += 4
            return v
        }

        mutating func unicodeEscape() throws -> Unicode.Scalar {
            var v = try hex4()
            if (0xD800..<0xDC00).contains(v), i + 1 < s.count, s[i] == "\\", s[i + 1] == "u" {
                i += 2
                let low = try hex4()
                v = 0x10000 + ((v - 0xD800) << 10) + (low &- 0xDC00)
            }
            guard let u = Unicode.Scalar(v) else { throw JSONError(message: "bad scalar") }
            return u
        }

        mutating func number() throws -> JSONValue {
            let start = i
            while i < s.count, "+-0123456789.eE".unicodeScalars.contains(s[i]) { i += 1 }
            guard let n = Double(String(String.UnicodeScalarView(s[start..<i]))) else {
                throw JSONError(message: "bad value at \(start)")
            }
            return .number(n)
        }
    }
}
