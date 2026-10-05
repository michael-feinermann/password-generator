import Darwin
import Foundation

/// Owned reference storage with no copy-on-write. All aliases observe the same wipe.
/// Locking pages is best effort; Swift, frameworks and registers can still make copies.
final class SensitiveBytes: @unchecked Sendable {
    let count: Int
    private let pointer: UnsafeMutableRawPointer
    private let allocationByteCount: Int
    private let lock = NSLock()
    private let pagesLocked: Bool
    private var cleared = false

    init(count: Int) {
        precondition(count >= 0)
        let pageSize = Int(getpagesize())
        precondition(count <= Int.max - pageSize)
        self.count = count
        allocationByteCount = max(1, (count + pageSize - 1) / pageSize) * pageSize
        guard let allocation = mmap(nil, allocationByteCount, PROT_READ | PROT_WRITE,
                                    MAP_PRIVATE | MAP_ANON, -1, 0),
              allocation != UnsafeMutableRawPointer(bitPattern: -1) else {
            preconditionFailure("Secret buffer allocation failed.")
        }
        pointer = allocation
        // Exclude other heap objects from the pages we lock, wipe and release.
        pagesLocked = mlock(pointer, allocationByteCount) == 0
    }

    var isCleared: Bool { lock.withLock { cleared } }

    func withUnsafeBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
        try lock.withLock {
            try body(UnsafeRawBufferPointer(start: pointer, count: count))
        }
    }

    func withLiveBytes<T>(_ body: (UnsafeRawBufferPointer) -> T) -> T? {
        lock.withLock {
            guard !cleared else { return nil }
            return body(UnsafeRawBufferPointer(start: pointer, count: count))
        }
    }

    func withUnsafeMutableBytes<T>(_ body: (UnsafeMutableRawBufferPointer) throws -> T) rethrows -> T {
        try lock.withLock {
            precondition(!cleared, "A cleared secret buffer cannot be rewritten.")
            return try body(UnsafeMutableRawBufferPointer(start: pointer, count: count))
        }
    }

    func clear() {
        lock.withLock {
            // memset_s must execute even if these bytes are never read again.
            _ = memset_s(pointer, allocationByteCount, 0, allocationByteCount)
            cleared = true
        }
    }

    deinit {
        clear()
        if pagesLocked { _ = munlock(pointer, allocationByteCount) }
        _ = munmap(pointer, allocationByteCount)
    }
}

/// Only use with trivial numeric element types, never references or Swift objects.
func wipeNumericArray<T: FixedWidthInteger>(_ array: inout [T]) {
    array.withUnsafeMutableBytes { bytes in
        guard let base = bytes.baseAddress, !bytes.isEmpty else { return }
        _ = memset_s(base, bytes.count, 0, bytes.count)
    }
}
