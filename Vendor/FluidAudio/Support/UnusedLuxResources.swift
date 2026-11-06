import Foundation
/// Keep the unused SDK's resource lookup source-compatible without redistributing its G2P data.
/// Neither LuxTTS nor its empty-resource adapter is exposed by the app's model catalog.
public enum LuxTtsG2pResources {
    public static let bundle = Bundle(for: EmptyResourceMarker.self)
}
private final class EmptyResourceMarker: NSObject {}
