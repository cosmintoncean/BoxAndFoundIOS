import Foundation
import Supabase

/// The one Supabase client: auth, postgrest, realtime, storage.
///
/// A plain shared instance rather than a dependency-injection container. The
/// Android client needs Hilt because Android constructs view models for you;
/// here the composition root is `BoxAndFoundApp`, and every type that needs the
/// client takes it as an initialiser parameter with this as the default, which
/// keeps tests able to pass their own.
enum SupabaseProvider {
    static let shared: SupabaseClient = {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else {
            preconditionFailure(
                """
                Supabase is not configured. Copy Config/Secrets.xcconfig.example to \
                Config/Secrets.xcconfig and fill in SUPABASE_URL and SUPABASE_ANON_KEY \
                from Supabase -> Project Settings -> API.
                """
            )
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()
}
