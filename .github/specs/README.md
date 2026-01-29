# Spec-Driven Development for dbatools

This directory contains specifications for dbatools features and commands. We use spec-driven development to ensure AI agents produce consistent, high-quality code that follows dbatools conventions.

## What is Spec-Driven Development?

Spec-driven development treats specifications as executable, living artifacts. Instead of coding first and documenting later, we start with a detailed specification that becomes the "source of truth" guiding AI agents through implementation.

## The Four-Phase Workflow

### 1. Specify
Create a high-level description of the new command or feature. Focus on:
- User journeys and desired outcomes
- Business requirements and constraints
- Expected behavior and edge cases

Use the `/specify` prompt or run: `specify init`

### 2. Plan
Provide technical direction including:
- dbatools coding standards (CLAUDE.md)
- SMO vs T-SQL decisions
- SQL Server version compatibility requirements
- Pipeline output patterns

Use the `/plan` prompt to generate a detailed implementation plan.

### 3. Tasks
Break the specification into small, reviewable chunks:
- Each task addresses a specific problem
- Tasks are independently testable
- Enables validation and course correction

Use the `/tasks` prompt to generate actionable items.

### 4. Implement
Execute tasks while following dbatools conventions:
- SMO-first approach
- Immediate pipeline output
- Proper parameter splatting
- SQL Server 2000+ compatibility where feasible

## Directory Structure

```
.github/specs/
├── README.md              # This file
├── templates/
│   ├── command.spec.md    # Template for new dbatools commands
│   └── feature.spec.md    # Template for feature additions
└── active/
    └── <feature-name>.spec.md  # Active specifications
```

## Using with Claude Code

1. Create a spec file in `.github/specs/active/`
2. Reference the spec in your prompt:
   ```
   Implement the specification in .github/specs/active/my-feature.spec.md
   ```
3. Claude will follow the spec, creating tasks and implementing incrementally

## Using with GitHub Copilot

1. Use the `/specify` slash command to generate a spec
2. Use the `/plan` slash command for implementation planning
3. Use the `/tasks` slash command to break work into chunks

## Best Practices

- **Be specific about SQL versions**: State minimum SQL Server version requirements
- **Reference existing commands**: Point to similar dbatools commands as examples
- **Include test scenarios**: Define expected test cases in the spec
- **Consider pipeline behavior**: Specify what objects should be emitted

## Example Workflow

```powershell
# 1. Create spec for new command
# See templates/command.spec.md

# 2. Ask Claude to implement
"Implement Get-DbaUserPermission following the spec in
.github/specs/active/get-dbauserpermission.spec.md"

# 3. Review generated tasks and code
# 4. Iterate on implementation
```

## Related Documentation

- [CLAUDE.md](/CLAUDE.md) - Coding standards and conventions
- [style.md](../prompts/style.md) - Test style requirements
- [smo-vs-tsql.md](../prompts/smo-vs-tsql.md) - SMO vs T-SQL guidance
- [pipeline-output.md](../prompts/pipeline-output.md) - Pipeline patterns
