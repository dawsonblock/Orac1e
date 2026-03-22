public final class SkillRegistry {

    private var skills: [String: any Skill] = [:]
    private var codeSkills: [String: any CodeSkill] = [:]

    public init() {}

    public func register(_ skill: any Skill) {
        skills[skill.name] = skill
    }

    public func register(_ skill: any CodeSkill) {
        codeSkills[skill.name] = skill
    }

    public func get(_ name: String) -> (any Skill)? {
        skills[name]
    }

    public func getCode(_ name: String) -> (any CodeSkill)? {
        codeSkills[name]
    }

    public static func live() -> SkillRegistry {
        let registry = SkillRegistry()
        registry.register(ClickSkill())
        registry.register(TypeSkill())
        registry.register(ScrollSkill())
        registry.register(OpenAppSkill())
        registry.register(SwitchWindowSkill())
        registry.register(NavigateURLSkill())
        registry.register(FillFormSkill())
        registry.register(ReadFileSkill())
        registry.register(ReadRepositorySkill())
        registry.register(SearchCodeSkill())
        registry.register(OpenFileSkill())
        registry.register(EditFileSkill())
        registry.register(WriteFileSkill())
        registry.register(GeneratePatchSkill())
        registry.register(RunBuildSkill())
        registry.register(RunTestsSkill())
        registry.register(RunFormatterSkill())
        registry.register(RunLinterSkill())
        registry.register(ParseBuildFailureSkill())
        registry.register(ParseTestFailureSkill())
        registry.register(GitStatusSkill())
        registry.register(GitBranchSkill())
        registry.register(GitCommitSkill())
        registry.register(GitPushSkill())
        return registry
    }
}
