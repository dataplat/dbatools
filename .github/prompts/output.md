# Output Validation Tests

**ADD** output validation tests to the Pester v5 test file `--FILEPATH--`. **APPLY ALL CHANGES DIRECTLY TO THE FILE AND SAVE IT.**

Follow the output validation guidelines below AND the coding standards in `style.md`. This is a dbatools PowerShell module test file.

Command name:
--CMDNAME--

Command source file:
--CMDSRC--

**IMPORTANT**: Write all changes directly to the file. Do not just describe the changes — implement them and save the updated file. Verify your changes adhere to ALL guidelines before saving.

---

## CRITICAL RULES

1. **DO NOT re-run the command.** Piggyback on an existing invocation using `-OutVariable`. Adding a second call doubles the test time for that file.
2. **DO NOT modify existing `It` blocks.** The only allowed change to existing code is adding `-OutVariable "global:dbatoolsciOutput"` to ONE existing command call.
3. **DO NOT touch any other tests** except to add the `-OutVariable` capture parameter.
4. **DO verify documentation accuracy.** If the `.OUTPUTS` section in the command source is missing or wrong, update it to match actual behavior AND write tests that match.
5. **ALL values must reflect the CURRENT dev branch.** Read the command source file to determine exact types and columns — do not guess or assume.

---

## WORKFLOW

Follow this exact order:

### Step 1: Baseline Test Run

```powershell
Invoke-ManualPester -Path --FILEPATH-- -TestIntegration
```

Record the test duration.

### Step 2: Read the Command Source

Open `--CMDSRC--` and identify:
- The `.OUTPUTS` section in comment-based help
- All `Select-DefaultView` calls (note `-Property`, `-ExcludeProperty`, and `-TypeName` parameters)
- The output object construction (SMO pipeline, `[PSCustomObject]@{...}`, or both)

### Step 3: Add the Output Tests

Follow the patterns below. Place the new `Context "Output validation"` block as the **last Context** inside the last `Describe $CommandName -Tag IntegrationTests` block.

### Step 4: Verify Test Run

```powershell
Invoke-ManualPester -Path --FILEPATH-- -TestIntegration
```

Record the new duration. It **must** be comparable to the baseline (within a few seconds). If it is significantly longer, you added a command execution — go back and fix it.

---

## CAPTURING OUTPUT WITHOUT RE-RUNNING

### Strategy: `-OutVariable` on an Existing Call

Find the **earliest** command invocation in the integration tests that returns representative output. Add `-OutVariable "global:dbatoolsciOutput"` to that call. This captures the output in a global variable without affecting existing behavior.

```powershell
# BEFORE — existing code:
$results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -ExcludeUser

# AFTER — same call with output capture added:
$results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -ExcludeUser -OutVariable "global:dbatoolsciOutput"
```

### Choosing the Capture Point

Search the test file for command invocations. Prefer these locations (in order):

1. **Describe-level BeforeAll** — Best. Runs once, available everywhere in that Describe.
2. **Context-level BeforeAll** — Good. `global:` scope persists for later Contexts.
3. **It block** — Acceptable. `global:` scope persists, but that It block must execute before the output Context.

**Requirements for the chosen call:**
- It must invoke `$CommandName` (not a helper or setup command)
- It must return at least one result object
- It must NOT already use `-OutVariable`

### The ArrayList Reality

`-OutVariable` wraps output in an `ArrayList`. This is fine — **always index with `[0]`** for single-object assertions:

```powershell
# Type check — works on ArrayList element:
$global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Database]

# Property check — works on ArrayList element:
$global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
```

### Pester 5 Scoping: Why `global:` Is Required

Pester 5 runs each `Context` in an isolated scope. A variable set in Context A's `BeforeAll` is **NOT** visible in Context B's `It` blocks. The `global:` prefix in `-OutVariable "global:dbatoolsciOutput"` forces the variable into the global scope, making it available across all Context boundaries.

**You MUST use `global:` — no exceptions.** Without it, the output Context cannot access the captured variable.

### Cleanup

Always null out the global variable after output tests:

```powershell
Context "Output validation" {
    AfterAll {
        $global:dbatoolsciOutput = $null
    }

    # It blocks here...
}
```

---

## DETERMINING EXPECTED VALUES

Before writing any test, you must determine the **actual** output characteristics by reading the command source file.

### Finding the Output Type

In the command source, identify what gets emitted to the pipeline:

| Source Pattern | Output Type |
|----------------|------------|
| SMO object piped to `Select-DefaultView` | The SMO .NET type (e.g., `Microsoft.SqlServer.Management.Smo.Database`) |
| `[PSCustomObject]@{...}` piped to `Select-DefaultView -TypeName X` | Custom dbatools type (`dbatools.X`) wrapping a PSCustomObject |
| `[PSCustomObject]@{...}` piped to `Select-DefaultView` (no TypeName) | `PSCustomObject` |
| `[PSCustomObject]@{...}` without `Select-DefaultView` | `PSCustomObject` |

### Finding Default Display Columns

Locate all `Select-DefaultView` calls in the command source:

```powershell
# Pattern A: Explicit property list — these ARE your expected columns
Select-DefaultView -InputObject $obj -Property ComputerName, InstanceName, SqlInstance, Name, Status

# Pattern B: Variable-based list — find where $defaults is defined
$defaults = "ComputerName", "InstanceName", "SqlInstance", "Name", "Status"
Select-DefaultView -InputObject $obj -Property $defaults

# Pattern C: ExcludeProperty (inverse — all props EXCEPT these are default columns)
Select-DefaultView -InputObject $obj -ExcludeProperty InternalProp1, InternalProp2
```

For Pattern A and B, the listed properties ARE your expected default columns.
For Pattern C, determine the full property list from the object construction, then subtract excluded properties.

### Finding All Properties (PSCustomObject)

For `[PSCustomObject]@{...}` output, every key in the hashtable literal is a property. List them all.

---

## TEST PATTERNS

### Pattern 1: SMO Object Output

When the command returns an SMO type (e.g., `Microsoft.SqlServer.Management.Smo.Database`):

- **Test the base type** — do NOT test individual SMO properties (Microsoft can change them between versions)
- **Test the default display columns** — these are controlled by dbatools via `Select-DefaultView`

```powershell
Context "Output validation" {
    AfterAll {
        $global:dbatoolsciOutput = $null
    }

    It "Should return the correct type" {
        $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Database]
    }

    It "Should have the correct default display columns" {
        $expectedColumns = @(
            "ComputerName",
            "InstanceName",
            "SqlInstance",
            "Name",
            "Status",
            "IsAccessible",
            "RecoveryModel",
            "LogReuseWaitStatus",
            "Size",
            "Compatibility",
            "Collation",
            "Owner",
            "Encrypted",
            "LastFullBackup",
            "LastDiffBackup",
            "LastLogBackup"
        )
        $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
        Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
    }

    It "Should have accurate .OUTPUTS documentation" {
        $help = Get-Help $CommandName -Full
        $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Database"
    }
}
```

### Pattern 2: PSCustomObject Output

When the command returns `[PSCustomObject]` — test **ALL** properties:

```powershell
Context "Output validation" {
    AfterAll {
        $global:dbatoolsciOutput = $null
    }

    It "Should return a PSCustomObject" {
        $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
    }

    It "Should have the expected properties" {
        $expectedProperties = @(
            "ComputerName",
            "InstanceName",
            "SqlInstance",
            "DateTime",
            "SourceServer",
            "DestinationServer",
            "Name",
            "Type",
            "Status",
            "Notes"
        )
        $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
        Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
    }

    It "Should have accurate .OUTPUTS documentation" {
        $help = Get-Help $CommandName -Full
        $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
    }
}
```

### Pattern 3: Custom dbatools Type (via `-TypeName`)

When the command uses `Select-DefaultView -TypeName <Name>`:

```powershell
Context "Output validation" {
    AfterAll {
        $global:dbatoolsciOutput = $null
    }

    It "Should have the custom dbatools type name" {
        $global:dbatoolsciOutput[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
    }

    It "Should have the correct default display columns" {
        $expectedColumns = @(
            "DateTime",
            "SourceServer",
            "DestinationServer",
            "Name",
            "Type",
            "Status",
            "Notes"
        )
        $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
        Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
    }

    It "Should have accurate .OUTPUTS documentation" {
        $help = Get-Help $CommandName -Full
        $help.returnValues.returnValue.type.name | Should -Not -BeNullOrEmpty
    }
}
```

---

## DOCUMENTATION ACCURACY

### What to Verify

The `.OUTPUTS` section in the command source must match actual behavior:

| Check | How |
|-------|-----|
| Type name is correct | `Get-Help` returnValues type matches actual `GetType().FullName` |
| Default columns are documented | Every column in `DefaultDisplayPropertySet` appears in `.OUTPUTS` |
| No phantom columns | Every column documented as "default display" actually exists in `DefaultDisplayPropertySet` |

### When `.OUTPUTS` Is Wrong or Missing

If the `.OUTPUTS` section does not match actual output:

1. **Update the `.OUTPUTS` section** in the command source file (`--CMDSRC--`) to match reality
2. Follow the documentation format from `typesncolumns.md`
3. Write the output validation tests to match the **actual** output (not the old docs)

**Do NOT write tests that match incorrect documentation.** Fix the docs first, then write tests.

---

## COMMANDS WITH MULTIPLE OUTPUT PATHS

Some commands return different types based on switches or conditions. For these:

- Capture each output path with a separate global variable
- Name them descriptively: `$global:dbatoolsciOutputDefault`, `$global:dbatoolsciOutputDetailed`
- Test each path in a separate `It` block
- Only add captures to calls that **already exist** in the test file — do not add new calls for untested paths

---

## COMMANDS WITH NO INTEGRATION TESTS

If the test file has **only unit tests** (no `Describe $CommandName -Tag IntegrationTests`), **skip output validation entirely**. Output tests require running the command against a live SQL Server instance.

---

## COMMANDS THAT RETURN NO OUTPUT

Some commands (e.g., `Remove-*`, `Set-*`) return no output by default, only when `-PassThru` is used. For these:

- If `-PassThru` is tested in the existing integration tests, capture that output
- If `-PassThru` is not tested, **skip output validation** — do not add a new call

---

## FORMATTING REQUIREMENTS

All code must follow dbatools style requirements:

- **Double quotes** for all strings
- **Aligned hashtable** `=` signs (if any hashtables are used)
- **OTBS** (One True Brace Style) formatting
- **`$PSItem`** instead of `$_`
- **No trailing spaces**
- **Multi-line arrays** with one element per line, double-quoted

```powershell
# CORRECT — aligned, double-quoted, one per line
$expectedColumns = @(
    "ComputerName",
    "InstanceName",
    "SqlInstance",
    "Name",
    "Status"
)

# WRONG — single-quoted, single line
$expectedColumns = @('ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Status')
```

---

## COMPLETE WALKTHROUGH EXAMPLE

Given a test file for `Get-DbaDatabase`:

### 1. Read the command source (`public/Get-DbaDatabase.ps1`)

Find:
- `.OUTPUTS` says `Microsoft.SqlServer.Management.Smo.Database`
- `Select-DefaultView` uses `-Property $defaults` where `$defaults` is defined as a list of 16 columns
- No `-TypeName` parameter, so it is a raw SMO object

### 2. Find the capture point in the test file

```powershell
# Existing code in the first IntegrationTests Context:
Context "Count system databases on localhost" {
    It "reports the right number of databases" {
        $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -ExcludeUser
        $results.Count | Should -Be 4
    }
}
```

Add `-OutVariable` to this call:

```powershell
Context "Count system databases on localhost" {
    It "reports the right number of databases" {
        $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -ExcludeUser -OutVariable "global:dbatoolsciOutput"
        $results.Count | Should -Be 4
    }
}
```

### 3. Add the output Context as the last Context in that Describe block

```powershell
Context "Output validation" {
    AfterAll {
        $global:dbatoolsciOutput = $null
    }

    It "Should return the correct type" {
        $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Database]
    }

    It "Should have the correct default display columns" {
        $expectedColumns = @(
            "ComputerName",
            "InstanceName",
            "SqlInstance",
            "Name",
            "Status",
            "IsAccessible",
            "RecoveryModel",
            "LogReuseWaitStatus",
            "Size",
            "Compatibility",
            "Collation",
            "Owner",
            "Encrypted",
            "LastFullBackup",
            "LastDiffBackup",
            "LastLogBackup"
        )
        $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
        Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
    }

    It "Should have accurate .OUTPUTS documentation" {
        $help = Get-Help $CommandName -Full
        $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Database"
    }
}
```

### 4. Compare test times

```
Baseline:   12.3s (before changes)
With tests: 12.5s (after changes — no additional command execution)
```

---

## VERIFICATION CHECKLIST

**Capture:**
- [ ] `-OutVariable "global:dbatoolsciOutput"` added to ONE existing command call
- [ ] No new command invocations added (test time unchanged)
- [ ] `global:` scope used (required for Pester 5 cross-Context access)
- [ ] Global variable nulled in AfterAll

**Type Validation:**
- [ ] Output type tested against actual type from command source
- [ ] SMO types: `Should -BeOfType [Full.Type.Name]`
- [ ] PSCustomObject: `Should -BeOfType [PSCustomObject]`
- [ ] Custom dbatools types: `PSObject.TypeNames[0]` checked

**Column Validation:**
- [ ] Default display columns match `Select-DefaultView -Property` list in command source
- [ ] For PSCustomObject: ALL properties listed and tested
- [ ] For SMO objects: only default display columns tested (not individual SMO properties)
- [ ] `Compare-Object` used to compare expected vs actual column lists

**Documentation:**
- [ ] `Get-Help` returnValues type matches actual output type
- [ ] `.OUTPUTS` section updated if it was missing or inaccurate
- [ ] Documentation format follows `typesncolumns.md` conventions

**Performance:**
- [ ] `Invoke-ManualPester` baseline time recorded before changes
- [ ] `Invoke-ManualPester` time after changes is comparable (within a few seconds)

**Style:**
- [ ] Double quotes for all strings
- [ ] Multi-line arrays with one element per line
- [ ] OTBS brace style
- [ ] `$PSItem` instead of `$_`
- [ ] No trailing spaces
- [ ] All rules from `style.md` and `migration.md` followed
- [ ] All comments preserved exactly as in original
