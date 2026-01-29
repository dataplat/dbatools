# Plan - Create Implementation Plan from Specification

Generate a detailed implementation plan for a dbatools specification.

## Input Required

**Specification File**: --SPECFILE--

## Instructions

Read the specification and create an implementation plan that:

1. **Validates the specification** against dbatools standards
2. **Identifies technical approach** (SMO vs T-SQL decisions)
3. **Lists files to create/modify**
4. **Defines implementation order**
5. **Highlights potential challenges**

## dbatools Technical Standards

### Code Style Requirements

- **No backticks** for line continuation - use splatting
- **No `= $true`** in parameter attributes - use `[Parameter(Mandatory)]`
- **No `::new()`** - use `New-Object` for PowerShell v3 compatibility
- **Splat for 3+ parameters** with `$splat<Purpose>` naming
- **Align hashtables** - equals signs line up vertically
- **Double quotes** for all strings

### Architecture Decisions

Reference these guides:
- SMO vs T-SQL: `.github/prompts/smo-vs-tsql.md`
- Pipeline output: `.github/prompts/pipeline-output.md`
- SQL version support: `.github/prompts/sql-version-support.md`
- Test style: `.github/prompts/style.md`

### File Organization

```
public/
├── <Verb>-Dba<Noun>.ps1      # Command implementation

tests/
├── <Verb>-Dba<Noun>.Tests.ps1 # Pester v5 tests

# Registration (modify existing):
├── dbatools.psd1              # Add to FunctionsToExport
├── dbatools.psm1              # Add to Export-ModuleMember
```

## Output Format

```markdown
# Implementation Plan: <Command Name>

## Specification Review
- [ ] Naming follows dbatools conventions
- [ ] SQL version requirements are appropriate
- [ ] Technical approach (SMO/T-SQL) is justified
- [ ] Output object includes standard properties

## Technical Approach

### SMO Usage
<Describe what will use SMO and why>

### T-SQL Usage
<Describe what will use T-SQL and why, or "None required">

### SQL Version Handling
<Describe version compatibility approach>

## Implementation Order

1. **Command scaffold** - Basic structure with parameters
2. **Core logic** - Main functionality implementation
3. **Error handling** - Stop-Function patterns
4. **Output formatting** - PSCustomObject emission
5. **Help documentation** - Comment-based help
6. **Tests** - Pester v5 test file
7. **Registration** - Add to psd1/psm1

## Files to Create

| File | Purpose |
|------|---------|
| `public/<Command>.ps1` | Main command |
| `tests/<Command>.Tests.ps1` | Pester tests |

## Files to Modify

| File | Change |
|------|--------|
| `dbatools.psd1` | Add to FunctionsToExport |
| `dbatools.psm1` | Add to Export-ModuleMember |

## Potential Challenges

1. <Challenge 1 and mitigation>
2. <Challenge 2 and mitigation>

## Dependencies

- Existing commands: <list>
- SMO classes: <list>

## Estimated Complexity

<Low/Medium/High> - <brief justification>
```
