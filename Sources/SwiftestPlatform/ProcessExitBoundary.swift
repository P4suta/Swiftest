public enum ProcessExitBoundary {
    public static func fail(_ diagnostic: String) -> Never {
        ABIAdapter.terminateFailure("swiftest: " + diagnostic + "\n")
    }
}
