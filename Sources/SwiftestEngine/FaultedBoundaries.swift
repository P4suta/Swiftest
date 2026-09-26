import Foundation
import SwiftestFaults
import SwiftestModel
import SwiftestPlatform

public enum FaultedProcessResult: Sendable {
    case completed(ProcessOutput)
    case injected(FaultOutcome)
}

public enum FaultedReadResult: Sendable {
    case completed(Data)
    case injected(FaultOutcome)
}

public enum FaultedClockResult: Sendable {
    case completed(DurationNanoseconds)
    case injected(FaultOutcome)
}

public enum FaultedBoundaries {
    public static func process(
        point: FaultPointID,
        injector: inout FaultInjector,
        executable: String,
        arguments: [String],
        workingDirectory: String?
    ) throws(PlatformError) -> FaultedProcessResult {
        let evaluation: FaultBoundaryEvaluation<ProcessOutput> = try FaultInjectionBoundary.evaluate(
            point: point,
            injector: &injector,
            operation: { () throws(PlatformError) -> ProcessOutput in
                try ProcessBoundary.run(
                    executable: executable,
                    arguments: arguments,
                    workingDirectory: workingDirectory
                )
            }
        )
        switch evaluation {
        case .completed(let output):
            return .completed(output)
        case .injected(_, let outcome):
            return .injected(outcome)
        }
    }

    public static func read(
        point: FaultPointID,
        injector: inout FaultInjector,
        path: String
    ) throws(PlatformError) -> FaultedReadResult {
        let evaluation: FaultBoundaryEvaluation<Data> = try FaultInjectionBoundary.evaluate(
            point: point,
            injector: &injector,
            operation: { () throws(PlatformError) -> Data in
                try FileSystemBoundary.read(path: path)
            }
        )
        switch evaluation {
        case .completed(let data):
            return .completed(data)
        case .injected(_, let outcome):
            return .injected(outcome)
        }
    }

    public static func clock(
        point: FaultPointID,
        injector: inout FaultInjector
    ) -> FaultedClockResult {
        let evaluation = FaultInjectionBoundary.evaluate(
            point: point,
            injector: &injector,
            operation: PlatformClock.monotonicNanoseconds
        )
        switch evaluation {
        case .completed(let duration):
            return .completed(duration)
        case .injected(_, let outcome):
            return .injected(outcome)
        }
    }
}
