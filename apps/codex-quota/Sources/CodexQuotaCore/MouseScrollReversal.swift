public enum MouseScrollReversal {
    /// Trackpad scroll gestures are continuous; physical mouse wheels are not.
    public static func shouldReverseVerticalAxis(isContinuous: Int64) -> Bool {
        isContinuous == 0
    }
}
