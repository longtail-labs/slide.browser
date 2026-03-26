CommandPaletteCore – Refactored, Composable Command Palette

Overview

- State machine + registry design using The Composable Architecture (TCA).
- Commands are data-first `CommandDefinition` values with activation rules and an entry style.
- Providers stream items for inline, async results (e.g., tasks, web search).
- Launch with scope (cmdL/cmdT/cmdK/cmdP) and optional preselected command.

Key Types

- `PaletteScope`: Launch scope; also controls features like web results.
- `PaletteContext`: Context passed to activation rules/providers.
- `CommandDefinition`: Declarative command (id, title, activation, entry).
- `CommandEntrySpec`: How a command behaves: `.direct(effect)`, `.withProvider(title, providerID)`, `.workflow(title, steps)`.
- `CommandProvider`: Protocol for streaming `CommandItem` arrays given a query/context.
- `CommandEffect`: Data-only effects bubbled to parent via `.delegate(.effectTriggered(...))`.

Register Commands & Providers

let registry = CommandRegistry()
registry.register(commands: [
  CommandDefinition(
    id: .init("viewTasks"),
    title: "View Tasks",
    activation: { _, _ in true },
    entry: .withProvider(title: "Tasks", providerID: "tasks")
  )
])
registry.registerProvider(id: "tasks", provider: TasksProvider())

Inject registry via TCA dependencies:

Store(initialState: CommandPaletteFeature.State()) {
  CommandPaletteFeature()
} withDependencies: { values in
  values.commandRegistry = registry
}

Open/Close

- Open with scope: `store.send(.open(scope: .cmdK, preselect: nil))`
- Open with preselected command: `store.send(.open(scope: .cmdP, preselect: CommandID("viewTasks")))`
- Close: `store.send(.close)`

Handle Effects

- Observe delegate actions from the feature in your parent domain and map `CommandEffect` to real app actions (navigation, open URL, etc.).

