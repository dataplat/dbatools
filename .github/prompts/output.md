# Output Validation Tests

Add output validation tests to the piped Pester v5 test file. Apply all changes directly and save.

## Rules

1. **Read the command source** (`public/<CommandName>.ps1`) to determine exact output types and columns — do not guess.
2. **Fix `.OUTPUTS` docs** in the command source if they're wrong or missing, then write tests matching actual behavior.
3. **DO NOT modify existing `It` blocks** beyond adding `-OutVariable`.
4. **Look at similar command test files** for patterns and conventions when unsure.
5. **If no integration tests exist**, add a `Describe -Tag IntegrationTests` block with the output validation context.
6. **If the command returns no output** (e.g., `Remove-*`) and no `-PassThru` call exists in existing tests, skip output validation.

## Test Setup

Before running any tests:

```powershell
Import-Module ./dbatools.psm1 -Force
. ./private/testing/Invoke-ManualPester.ps1
```

## Workflow

1. Run `Invoke-ManualPester -Path <testfile> -TestIntegration` — record baseline time
2. Read the command source — find `.OUTPUTS`, `Select-DefaultView` calls, and output object construction
3. Add `-OutVariable "global:dbatoolsciOutput"` to one existing command call (if integration tests exist)
4. Add a new `Context "Output validation"` as the **last Context** in the last `Describe -Tag IntegrationTests` block
5. Run `Invoke-ManualPester -Path <testfile> -TestIntegration` again — time must be comparable to baseline
6. If there are failures, log them to `/tmp/output-validation-failures.md` with the command name, failure message, and what you tried
7. Commit modified files

## Failure Tracking

If tests fail, append to `/tmp/output-validation-failures.md`:

```markdown
## CommandName
- **Failure**: Description of what failed
- **Attempted**: What you tried to fix it
- **Status**: Fixed / Skipped / Needs manual review
```

## Capturing Output

Find the earliest command invocation that returns representative output. Add `-OutVariable "global:dbatoolsciOutput"` to it. This piggybacks on the existing call — no re-execution, no added test time.

Use `global:` scope — Pester 5 isolates each Context, so without it the output validation Context can't see the variable.

`-OutVariable` wraps output in an ArrayList — index with `[0]` for assertions.

Always clean up:

```powershell
Context "Output validation" {
    AfterAll {
        $global:dbatoolsciOutput = $null
    }
    # tests here
}
```

## Determining Expected Values

Read the command source to find:

| Source Pattern | Output Type |
|---|---|
| SMO object → `Select-DefaultView` | The SMO .NET type |
| `[PSCustomObject]` → `Select-DefaultView -TypeName X` | Custom type (`dbatools.X`) |
| `[PSCustomObject]` → `Select-DefaultView` (no TypeName) | `PSCustomObject` |
| `[PSCustomObject]` without `Select-DefaultView` | `PSCustomObject` |

Default display columns come from `Select-DefaultView -Property` (or invert `-ExcludeProperty`).

## Test Patterns

### SMO Object

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
            "SqlInstance"
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

### PSCustomObject — test ALL properties

```powershell
It "Should return a PSCustomObject" {
    $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
}

It "Should have the expected properties" {
    $expectedProperties = @(
        "ComputerName",
        "InstanceName",
        "SqlInstance"
    )
    $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
    Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
}
```

### Custom dbatools Type (via `-TypeName`)

```powershell
It "Should have the custom dbatools type name" {
    $global:dbatoolsciOutput[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
}
```

Use the default display columns test from the SMO pattern for the columns check.

## Style

- Double quotes for all strings
- Multi-line arrays, one element per line
- OTBS brace style
- `$PSItem` not `$_`