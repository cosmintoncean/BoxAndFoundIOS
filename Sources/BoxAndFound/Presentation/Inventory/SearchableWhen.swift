import SwiftUI

extension View {
    /// `.searchable` only when there is something to search.
    ///
    /// The `isPresented:` overload looks like the way to do this, but it wants
    /// a two-way binding it can flip when the person dismisses the field —
    /// handing it a constant would silently take away their ability to close
    /// the search. Branching on the modifier instead leaves the search bar's
    /// own behaviour alone.
    @ViewBuilder
    func searchableWhen(
        _ visible: Bool,
        text: Binding<String>,
        prompt: String
    ) -> some View {
        if visible {
            searchable(text: text, prompt: prompt)
        } else {
            self
        }
    }
}
