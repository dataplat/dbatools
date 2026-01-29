# Specify - Generate a dbatools Command Specification

Generate a comprehensive specification for a new dbatools PowerShell command.

## Input Required

**Command Name**: --CMDNAME--
**Purpose**: --PURPOSE--
**Similar Commands**: --SIMILAR-- (existing dbatools commands to reference)

## Instructions

Create a detailed specification following the template at `.github/specs/templates/command.spec.md`.

### Key Considerations for dbatools

1. **Naming Convention**
   - Use singular nouns: `Get-DbaDatabase` not `Get-DbaDatabases`
   - Follow `<Verb>-Dba<Noun>` pattern
   - Use approved PowerShell verbs

2. **SQL Server Version Support**
   - Default to SQL Server 2000 support when feasible
   - If feature requires newer version, specify minimum and handle gracefully
   - Use `Connect-DbaInstance -MinimumVersion X` for version requirements

3. **Technical Approach**
   - Default to SMO for object manipulation
   - Use T-SQL only for DMVs, system views, or version-specific logic
   - Reference `.github/prompts/smo-vs-tsql.md` for guidance

4. **Pipeline Behavior**
   - Objects must be emitted immediately to pipeline
   - Never collect in ArrayList or arrays
   - Reference `.github/prompts/pipeline-output.md`

5. **Standard Parameters**
   - SqlInstance (DbaInstanceParameter[])
   - SqlCredential (PSCredential)
   - EnableException (Switch)
   - Add command-specific parameters as needed

6. **Output Object**
   - Include: ComputerName, InstanceName, SqlInstance
   - Use custom type: `Sqlcollaborative.Dbatools.<TypeName>`
   - Emit consistent objects for pipeline chaining

## Output

Generate the specification and save it to:
`.github/specs/active/<command-name>.spec.md`

Include:
- Clear functional requirements
- Technical design decisions (SMO vs T-SQL)
- Test scenarios (unit and integration)
- Edge cases and error handling
- Acceptance criteria
