import Foundation

/// What every screen in this app is made of.
///
/// **The shape, and why it is not textbook MVP.** Classic MVP hands the
/// presenter a reference to a `View` protocol and has it call `render(state)`.
/// SwiftUI views are structs, recreated on every state change and never worth
/// holding a reference to, so that half inverts: the presenter publishes one
/// `viewState` and SwiftUI does the calling. What survives — and what makes it
/// MVP rather than MVVM — is that the view is *passive*:
///
/// - It owns no state of its own. It holds the presenter, and `@FocusState`
///   because the keyboard is genuinely a view concern; nothing else. No
///   `@Binding` into the presenter, no logic in `body` past `if` and `ForEach`.
/// - It never sees a domain type. `viewState` is a UI model: strings already
///   worded, flags already decided, lists already ordered.
/// - Every user action is an intent — a method on the presenter. A keystroke
///   is `emailChanged(_:)`, not a two-way binding that mutates a field behind
///   the presenter's back.
///
/// The payoff is that a screen's whole behaviour is testable by calling
/// methods and reading `viewState`, with no view involved, and that swapping
/// how something looks cannot change what it does.
///
/// `viewState` is deliberately get-only: it is derived from private state the
/// presenter owns, so there is exactly one way for it to change.
@MainActor
protocol Presenter<ViewState>: AnyObject {
    associatedtype ViewState: Equatable

    var viewState: ViewState { get }
}
