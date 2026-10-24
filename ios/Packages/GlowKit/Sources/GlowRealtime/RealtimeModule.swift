import AppCore
import Foundation

// Owner: B5. The spec calls this module "Realtime"; it is GlowRealtime because supabase-swift
// already has a target named Realtime, and SwiftPM needs unique target names (D41).
// The app target calls `live` in AppComposition; keep its signature.

public enum RealtimeModule {
    /// The realtime service the app runs on: Supabase Realtime private channels. Without a
    /// configured Supabase URL and anon key (an unconfigured Release build), it never connects.
    public static func live(_ context: ServiceContext) -> any RealtimeService {
        guard let url = context.config.supabaseURL, !context.config.supabaseAnonKey.isEmpty else {
            return PreviewRealtimeService(state: .disconnected)
        }
        return LiveRealtimeService(supabaseURL: url, anonKey: context.config.supabaseAnonKey, session: context.session)
    }
}
