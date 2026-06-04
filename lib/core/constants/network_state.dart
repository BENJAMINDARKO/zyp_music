/// Reactive network state of the device, as observed by the
/// global [ConnectivityService].
///
/// Transitions are emitted in [ConnectivityService.initialize]:
///
/// * [NetworkState.unknown]  — the initial state, used before the first
///                             connectivity probe has completed.
/// * [NetworkState.online]   — at least one transport (`mobile`, `wifi`,
///                             `ethernet`, `vpn`, ...) is reachable.
/// * [NetworkState.offline]  — no transport is reachable; data sources
///                             should be restricted to local caches.
enum NetworkState { unknown, online, offline }
