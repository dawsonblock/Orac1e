import SwiftUI
import OracleControllerShared

struct RecipesWorkspaceView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            PanelCard("Recipe Library", subtitle: "Existing replayable workflows") {
                TextField("Search recipes", text: $store.recipeSearchText)
                    .textFieldStyle(.roundedBorder)

                List(store.filteredRecipes, selection: $store.selectedRecipeName) { recipe in
                    Button {
                        Task { await store.selectRecipe(named: recipe.name) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.name)
                                .font(.system(size: 13, weight: .semibold))
                            Text(recipe.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                    .tag(recipe.name)
                }
                .frame(minHeight: 420)

                HStack {
                    Button("New") {
                        store.createRecipe()
                    }
                    Button("Duplicate") {
                        store.duplicateSelectedRecipe()
                    }
                    .disabled(store.selectedRecipeName == nil)
                    Button("Delete", role: .destructive) {
                        Task { await store.deleteSelectedRecipe() }
                    }
                    .disabled(store.selectedRecipeName == nil)
                }
            }
            .frame(width: 320)

            RecipeEditorView(store: store)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
    }
}

struct RecipeEditorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        PanelCard("Recipe Editor", subtitle: "Form editing over the current JSON schema") {
            HStack {
                Picker("Mode", selection: $store.recipeEditorMode) {
                    ForEach(RecipeEditorMode.allCases) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                Button {
                    Task { await store.saveDraftRecipe() }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(ControllerTheme.accent)
            }

            if store.recipeEditorMode == .raw {
                TextEditor(text: $store.rawRecipeText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 520)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ControllerTheme.border, lineWidth: 1)
                    )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Recipe name", text: $store.draftRecipe.name)
                            .textFieldStyle(.roundedBorder)
                        TextField("Description", text: $store.draftRecipe.description)
                            .textFieldStyle(.roundedBorder)
                        TextField("App", text: stringBinding($store.draftRecipe.app))
                            .textFieldStyle(.roundedBorder)
                        TextField("Global failure policy", text: stringBinding($store.draftRecipe.onFailure))
                            .textFieldStyle(.roundedBorder)

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Parameters")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Button("Add Param") {
                                    store.addRecipeParam()
                                }
                            }

                            if let paramKeys = store.draftRecipe.params?.keys.sorted(), !paramKeys.isEmpty {
                                ForEach(paramKeys, id: \.self) { key in
                                    RecipeParameterRow(store: store, paramKey: key)
                                }
                            } else {
                                Text("No parameters defined.")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Steps")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Button("Add Step") {
                                    store.addRecipeStep()
                                }
                            }

                            ForEach(Array(store.draftRecipe.steps.enumerated()), id: \.element.id) { index, step in
                                RecipeStepCard(store: store, stepIndex: index, step: step)
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(minHeight: 520)
            }
        }
    }
}

struct RecipeParameterRow: View {
    @Bindable var store: ControllerStore
    let paramKey: String

    var body: some View {
        let paramBinding = Binding<RecipeParamDocument>(
            get: { store.draftRecipe.params?[paramKey] ?? RecipeParamDocument(id: paramKey, type: "string", description: "", required: true) },
            set: { updated in
                var params = store.draftRecipe.params ?? [:]
                params[paramKey] = updated
                store.draftRecipe.params = params
            }
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(paramKey)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Remove", role: .destructive) {
                    store.removeRecipeParam(id: paramKey)
                }
            }
            TextField("Type", text: paramBinding.type)
                .textFieldStyle(.roundedBorder)
            TextField("Description", text: paramBinding.description)
                .textFieldStyle(.roundedBorder)
            Toggle("Required", isOn: paramBinding.required)
        }
        .padding(12)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct RecipeStepCard: View {
    @Bindable var store: ControllerStore
    let stepIndex: Int
    let step: RecipeStepDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Step \(step.id)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Remove", role: .destructive) {
                    store.removeRecipeStep(id: step.id)
                }
            }

            TextField("Action", text: binding(\.action))
                .textFieldStyle(.roundedBorder)
            TextField("Note", text: stringBinding(binding(\.note)))
                .textFieldStyle(.roundedBorder)
            TextField("Failure policy", text: stringBinding(binding(\.onFailure)))
                .textFieldStyle(.roundedBorder)
            TextField(
                "Target contains (advanced locators remain available in raw mode)",
                text: Binding(
                    get: { store.draftRecipe.steps[stepIndex].target?.computedNameContains ?? "" },
                    set: { newValue in
                        var target = store.draftRecipe.steps[stepIndex].target ?? LocatorDocument()
                        target.computedNameContains = newValue.isEmpty ? nil : newValue
                        store.draftRecipe.steps[stepIndex].target = target
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            TextField(
                "Wait after condition",
                text: Binding(
                    get: { store.draftRecipe.steps[stepIndex].waitAfter?.condition ?? "" },
                    set: { newValue in
                        var waitAfter = store.draftRecipe.steps[stepIndex].waitAfter ?? RecipeWaitConditionDocument(condition: newValue)
                        waitAfter.condition = newValue
                        store.draftRecipe.steps[stepIndex].waitAfter = newValue.isEmpty ? nil : waitAfter
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            TextField(
                "Wait after value",
                text: Binding(
                    get: { store.draftRecipe.steps[stepIndex].waitAfter?.value ?? "" },
                    set: { newValue in
                        var waitAfter = store.draftRecipe.steps[stepIndex].waitAfter ?? RecipeWaitConditionDocument(condition: "elementExists")
                        waitAfter.value = newValue.isEmpty ? nil : newValue
                        store.draftRecipe.steps[stepIndex].waitAfter = waitAfter
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<RecipeStepDocument, Value>) -> Binding<Value> {
        Binding(
            get: { store.draftRecipe.steps[stepIndex][keyPath: keyPath] },
            set: { store.draftRecipe.steps[stepIndex][keyPath: keyPath] = $0 }
        )
    }
}

struct RecipeInspectorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PanelCard("Run Recipe", subtitle: "Execute the selected workflow with explicit parameters") {
                    if let params = store.draftRecipe.params, !params.isEmpty {
                        ForEach(params.keys.sorted(), id: \.self) { key in
                            TextField(
                                key,
                                text: Binding(
                                    get: { store.recipeRunParameters[key] ?? "" },
                                    set: { store.recipeRunParameters[key] = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        Text("This recipe does not declare any runtime parameters.")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await store.runSelectedRecipe() }
                    } label: {
                        Label("Run Selected Recipe", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ControllerTheme.accent)
                }

                PanelCard("Last Run", subtitle: "Structured replay results") {
                    if let latestRecipeRun = store.latestRecipeRun {
                        HStack {
                            StatusBadge(
                                label: latestRecipeRun.paused ? "Paused" : (latestRecipeRun.success ? "Succeeded" : "Failed"),
                                tone: latestRecipeRun.paused ? .warning : (latestRecipeRun.success ? .good : .danger)
                            )
                            Text("\(latestRecipeRun.stepsCompleted)/\(latestRecipeRun.totalSteps) steps")
                                .font(.system(size: 12, design: .monospaced))
                        }
                        if let pendingApprovalRequestID = latestRecipeRun.pendingApprovalRequestID {
                            KVRow(key: "Pending Approval", value: pendingApprovalRequestID, monospaced: true)
                        }
                        if let resumeToken = latestRecipeRun.resumeToken {
                            KVRow(key: "Resume Token", value: resumeToken, monospaced: true)
                        }
                        if let error = latestRecipeRun.error {
                            Text(error)
                                .foregroundStyle(ControllerTheme.danger)
                        }
                        ForEach(latestRecipeRun.stepResults) { step in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.action)
                                        .font(.system(size: 12, weight: .semibold))
                                    if let note = step.note {
                                        Text(note)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(step.durationMs) ms")
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "play.rectangle.on.rectangle",
                            title: "No Run Yet",
                            message: "Run a recipe to inspect structured results and linked trace output."
                        )
                        .frame(height: 220)
                    }
                }
            }
            .padding(20)
        }
    }
}

private func stringBinding(_ source: Binding<String?>, defaultValue: String = "") -> Binding<String> {
    Binding<String>(
        get: { source.wrappedValue ?? defaultValue },
        set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
    )
}
