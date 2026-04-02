import Foundation

struct RemoteFileFilesystemStatus: Hashable, Sendable {
    let blockSize: UInt64
    let totalBlocks: UInt64
    let freeBlocks: UInt64
    let availableBlocks: UInt64

    var totalBytes: UInt64 {
        blockSize.saturatingMultiply(totalBlocks)
    }

    var freeBytes: UInt64 {
        blockSize.saturatingMultiply(freeBlocks)
    }

    var availableBytes: UInt64 {
        blockSize.saturatingMultiply(availableBlocks)
    }
}

struct RemoteFileBreadcrumb: Identifiable, Hashable, Sendable {
    let title: String
    let path: String

    var id: String { path }
}

private extension UInt64 {
    func saturatingMultiply(_ other: UInt64) -> UInt64 {
        multipliedReportingOverflow(by: other).partialValue
    }
}
