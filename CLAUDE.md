# dbatools

The community PowerShell module for SQL Server professionals. This file covers the conventions
that differ from ordinary modern PowerShell — the ones you cannot infer from the surrounding code.

## Hard constraints

**PowerShell v3 must keep working.** No `::new()` and no other v5+ syntax — use
`New-Object -TypeName System.Collections.Hashtable`.

**Never use backticks for line continuation.** Splat instead. Under 3 parameters, pass them
directly; at 3 or more use a splatted hashtable named `$splat<Purpose>` (never a bare `$splat`),
with the `=` signs aligned:

```powershell
$database = Get-DbaDatabase -SqlInstance $instance -Name "master"

$splatConnection = @{
    SqlInstance     = $instance
    SqlCredential   = $TestConfig.SqlCredential
    Database        = $dbName
    EnableException = $true
    Confirm         = $false
}
$result = New-DbaDatabase @splatConnection
```

Alignment applies to every hashtable, not just splats. Variable names must be unique across
scopes — collisions have caused real bugs here.

**Parameter attributes use the modern form**: `[Parameter(Mandatory)]`, not
`[Parameter(Mandatory = $true)]`. Use `[switch]` for flags, never `[bool]`. Avoid ParameterSets —
use `Test-Bound` with a useful error message instead. No blank lines between parameter
declarations.

**Double quotes for all strings**, escaping inner quotes as `` `" `` — the SQL Server module
standard, even when the string has nothing to interpolate.

**Output to the pipeline immediately.** Never accumulate into an ArrayList or array and emit at
the end:

```powershell
foreach ($db in $server.Databases) {
    [PSCustomObject]@{
        ComputerName = $server.ComputerName
        Database     = $db.Name
    }
}
```

**Preserve every comment exactly as written** — including development notes, temporary comments,
CI/CD markers, and anything resembling `#$TestConfig.instance...`. AppVeyor metadata in particular
looks like dead text and is not.

OTBS braces, 4-space indent, no trailing whitespace.

## Conventions

**Naming**: `<Verb>-Dba<Noun>`, approved verbs, **singular** nouns (`Get-DbaDatabase`, not
`Get-DbaDatabases`). No `-Detailed`/`-Simple` output-mode switches. A `-Pattern` parameter is
always **regex** — never SQL `LIKE`, never PowerShell wildcards.

**Registering a new command takes two edits**: the `FunctionsToExport` array in `dbatools.psd1`,
*and* the explicit export section in `dbatools.psm1`. New commands list "the dbatools team +
Claude" as author in `.NOTES`.

**Commit messages and PR titles must carry a `(do ...)` line** — it scopes the CI run:

```
Get-DbaDatabase - Add support for filtering by recovery model

(do Get-DbaDatabase)
```

Wildcards and lists work: `(do *Login*)`, `(do *Backup*, *Restore*)`.

**SQL Server version support**: aim for SQL 2000 where feasible and skip gracefully where a
feature needs 2005+ — never dismissively, people really do run these. Version 8 = 2000, 9 = 2005,
11 = 2012; `Connect-DbaInstance -MinimumVersion 9` expresses a 2005+ floor.

**SMO vs T-SQL**: default to SMO for object manipulation, scripting, and property access. Reach
for T-SQL for system views, DMVs, stored procedures, and version-specific logic.

**Tests**: update parameter-validation tests whenever parameters change, add 1–3 focused tests for
new behavior, and use `EnableException` in `BeforeAll`/`AfterAll`.

## Tone: warm and short

Talk like a friendly colleague who is busy — kind, plain, and finished in a few lines. The warmth
is in the wording, not in extra words.

**Prose**: lead with the answer or the result, and add detail only when it changes what happens
next. No preamble, no restating the request back, no closing paragraph that summarizes the opening
one. Say "I'm not sure" once instead of hedging three times.

**Comments**: explain *why*, never *what*. If the code already says it, delete the comment. No
banners, no `# Step 1:` narration, no comment above a function that restates its parameters. A
version quirk, a non-obvious workaround, a constraint that cost real debugging — those earn a line.
Comment-based help (`.SYNOPSIS`/`.EXAMPLE`/`.OUTPUTS`) is required and not covered by this, and
neither is the rule above about preserving existing comments exactly.

## Deeper references

Read these when the task lands in one of them, rather than up front.

| Topic | File |
| --- | --- |
| SQL version support patterns | `.github/prompts/sql-version-support.md` |
| SMO vs T-SQL guidance | `.github/prompts/smo-vs-tsql.md` |
| Pipeline output patterns | `.github/prompts/pipeline-output.md` |
| Generating `.OUTPUTS` docs (all commands need them) | `.github/prompts/typesncolumns.md` |
| Test style | `.github/prompts/style.md` |
| Pester v5 migration | `.github/prompts/migration.md` |

## The 3.0 library migration

This repo is one of three in an active campaign porting these commands to C#. The coordination
repo, specs, and issue queue live in `migration/` — **read `migration/CLAUDE.md` before touching a
command that is being ported.** The C# side is `../dbatools.library`. Both code repos work on
branch `libmigration`.
