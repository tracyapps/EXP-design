// exp-mcp — MCP stdio ↔ EXP's current-user Unix socket.
// This helper owns no design logic and never opens a network connection.

import Foundation
import Darwin

private let unavailableMessage =
    "EXP is not running, or agent access is disabled in EXP's Handoff panel"

private func socketPath() -> String {
    let home: String
    if let record = getpwuid(getuid()), let path = record.pointee.pw_dir {
        home = String(cString: path)
    } else {
        home = "/Users/Shared"
    }
    return home + "/Library/Containers/tapps.EXP--design-/Data/Library/Application Support/EXP/agent.sock"
}

private func connectToEXP() -> Int32? {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let path = socketPath().utf8CString
    guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        Darwin.close(fd)
        return nil
    }
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
        path.withUnsafeBytes { source in destination.copyBytes(from: source) }
    }
    let length = MemoryLayout.offset(of: \sockaddr_un.sun_path)! + path.count
    address.sun_len = UInt8(length)
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(length))
        }
    }
    guard result == 0 else {
        Darwin.close(fd)
        return nil
    }
    return fd
}

private func writeAll(_ data: Data, to fd: Int32) -> Bool {
    data.withUnsafeBytes { raw in
        guard var base = raw.baseAddress else { return true }
        var remaining = raw.count
        while remaining > 0 {
            let written = Darwin.write(fd, base, remaining)
            if written < 0, errno == EINTR { continue }
            if written <= 0 { return false }
            base = base.advanced(by: written)
            remaining -= written
        }
        return true
    }
}

private func unavailableResponse(for line: String) -> Data? {
    guard let data = line.data(using: .utf8),
          let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          request["id"] != nil else { return nil } // notifications have no response
    let response: [String: Any] = [
        "jsonrpc": "2.0",
        "id": request["id"]!,
        "error": ["code": -32001, "message": unavailableMessage]
    ]
    guard let encoded = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]) else {
        return nil
    }
    return encoded + Data([0x0A])
}

private func answerUnavailable() {
    while let line = readLine(strippingNewline: true) {
        if let response = unavailableResponse(for: line) {
            _ = writeAll(response, to: STDOUT_FILENO)
        }
    }
}

private func relay(socket fd: Int32) {
    var inputOpen = true
    var descriptors = [
        pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0),
        pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    ]
    var buffer = [UInt8](repeating: 0, count: 32_768)

    while true {
        descriptors[0].events = inputOpen ? Int16(POLLIN) : 0
        descriptors[0].revents = 0
        descriptors[1].revents = 0
        let ready = Darwin.poll(&descriptors, nfds_t(descriptors.count), -1)
        if ready < 0, errno == EINTR { continue }
        if ready <= 0 { return }

        if inputOpen, descriptors[0].revents & Int16(POLLIN | POLLHUP) != 0 {
            let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
            if count > 0 {
                if !writeAll(Data(buffer.prefix(count)), to: fd) { return }
            } else {
                inputOpen = false
                _ = Darwin.shutdown(fd, SHUT_WR)
            }
        }

        if descriptors[1].revents & Int16(POLLIN | POLLHUP | POLLERR) != 0 {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                if !writeAll(Data(buffer.prefix(count)), to: STDOUT_FILENO) { return }
            } else {
                return
            }
        }
    }
}

if let socket = connectToEXP() {
    relay(socket: socket)
    Darwin.close(socket)
} else {
    answerUnavailable()
}
