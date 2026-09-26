import Darwin
import Foundation

enum ABIAdapter {
    static func openLock(at path: String) -> Int32 {
        Darwin.open(path, O_CREAT | O_EXCL | O_RDWR, S_IRUSR | S_IWUSR)
    }

    static func releaseLock(_ descriptor: Int32, path: String) {
        let closeResult = Darwin.close(descriptor)
        let unlinkResult = Darwin.unlink(path)
        if closeResult == Int32.min || unlinkResult == Int32.min {
            preconditionFailure("unreachable release status")
        }
    }

    static func monotonicNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}
