# Output Validation Test Generator for dbatools

You are analyzing a dbatools test file to add output validation tests for the C# migration to dbatools 3.0.

## Your Task

Given a test file (*.Tests.ps1):

1. Find the corresponding command in `public/` (same base name)
2. Analyze the command's output patterns
3. Update `.OUTPUTS` documentation if missing/incomplete
4. Add output validation tests to the test file

**Edit both files directly using your Edit/Write tools.**

---

## Step 1: Find the Command File

The test file name maps to the command:
- `Get-DbaDatabase.Tests.ps1` -> `public/Get-DbaDatabase.ps1`
- `Backup-DbaDatabase.Tests.ps1` -> `public/Backup-DbaDatabase.ps1`

Read the command file to analyze its output.

---

## Step 2: Analyze Output Patterns

### Find Default Display Properties

Look for `Select-DefaultView` calls:

```powershell
# Pattern 1: Inline
Select-DefaultView -InputObject $obj -Property ComputerName, InstanceName, SqlInstance, Name

# Pattern 2: Variable
$defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Size as SizeMB'
Select-DefaultView -InputObject $obj -Property $defaults

# Pattern 3: Conditional additions
if ($IncludeLastUsed) {
    $defaults += ('LastRead as LastIndexRead', 'LastWrite as LastIndexWrite')
}
```

**IMPORTANT - Property Aliases:** When you see `'Size as SizeMB'`, the property name is `SizeMB` (the alias), not `Size`.

### Find Added Properties

Look for `Add-Member` calls:
```powershell
Add-Member -Force -InputObject $db -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
```

### Determine Output Type

- SMO objects: Look for what's being piped to Select-DefaultView (e.g., `$server.Databases`)
- Custom types: `New-Object Dataplat.Dbatools.*`
- PSCustomObject: `[PSCustomObject]@{...}`

### Find Output-Modifying Switches

Common switches that add properties:
- `-Detailed` - adds detailed properties
- `-Raw` - returns different type (often System.String or DataRow)
- `-IncludeLastUsed` - adds usage tracking properties
- `-NoFullBackup` / `-NoFullBackupSince` - adds BackupStatus
- `-Passthru` - returns output when command normally doesn't

---

## Step 3: Update .OUTPUTS Documentation

If `.OUTPUTS` is missing or incomplete, add/update it in the command file.

### Format

```
.OUTPUTS
    Microsoft.SqlServer.Management.Smo.TypeName

    Brief description of what is returned and how many objects.

    Default display properties (via Select-DefaultView):
    - ComputerName: The computer name of the SQL Server instance
    - InstanceName: The SQL Server instance name
    - SqlInstance: The full SQL Server instance name (computer\instance)
    - Name: Object name
    [... other properties from Select-DefaultView ...]

    When -SwitchName is specified, additional properties are included:
    - PropertyName: Description

    Additional properties available (access via Select-Object *):
    - All standard SMO TypeName properties are accessible
```

### Rules

1. Place after last `.PARAMETER`, before first `.EXAMPLE`
2. Use alias names (SizeMB not Size)
3. For SMO objects, don't list all SMO properties - just mention they're accessible
4. Document each output-modifying switch

---

## Step 4: Add Output Validation Tests

Add tests to the test file. Insert as a new Context within the existing Describe block, or create a new Describe if needed.

### Basic Template

```powershell
Context "Output Validation" {
    BeforeAll {
        $result = CommandName -SqlInstance $TestConfig.instance1 -Database master -EnableException
    }

    It "Returns the documented output type" {
        $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.TypeName]
    }

    It "Has the expected default display properties" {
        $expectedProps = @(
            'ComputerName',
            'InstanceName',
            'SqlInstance',
            'Name'
            # Add all properties from Select-DefaultView here
        )
        $actualProps = $result.PSObject.Properties.Name
        foreach ($prop in $expectedProps) {
            $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
        }
    }
}
```

### For PSCustomObject (no specific type)

```powershell
It "Returns PSCustomObject" {
    $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
}
```

### For Conditional Switches

Add separate contexts:

```powershell
Context "Output with -IncludeLastUsed" {
    BeforeAll {
        $result = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master -IncludeLastUsed -EnableException
    }

    It "Includes LastIndexRead and LastIndexWrite properties" {
        $result.PSObject.Properties.Name | Should -Contain 'LastIndexRead'
        $result.PSObject.Properties.Name | Should -Contain 'LastIndexWrite'
    }
}
```

### For -Raw or Different Output Types

```powershell
Context "Output with -Raw" {
    BeforeAll {
        $result = Get-DbaDbBackupHistory -SqlInstance $TestConfig.instance1 -Raw -EnableException
    }

    It "Returns DataRow when -Raw specified" {
        $result | Should -BeOfType [System.Data.DataRow]
    }
}
```

---

## Important Rules

### DO:
- Test property EXISTENCE, not values
- Use alias names from Select-DefaultView
- Include `-EnableException` in BeforeAll blocks
- Use `$TestConfig.instance1` for SQL instances
- Keep parameter usage minimal (just enough to get output)

### DO NOT:
- Test ALL SMO properties (Microsoft could add more, breaking tests)
- Test property VALUES (unless explicitly set by dbatools)
- Add duplicate contexts if "Output Validation" already exists
- Generate tests for commands that return nothing

### Property Categories

**Always test (dbatools controls these):**
- ComputerName, InstanceName, SqlInstance
- All properties in Select-DefaultView -Property
- All properties added via Add-Member

**Never exhaustively test:**
- Native SMO properties beyond what dbatools adds
- Internal/private properties

---

## Special Cases

### Commands with no output
Some commands (Set-*, Remove-*, Write-*) don't output by default. If the command has no Select-DefaultView and no explicit output, skip output validation unless -Passthru exists.

### Commands with -Passthru
Test both behaviors:
```powershell
Context "Output without -Passthru" {
    It "Returns no output by default" {
        $result = Set-DbaDbState -SqlInstance $TestConfig.instance1 -Database tempdb -ReadOnly -EnableException
        $result | Should -BeNullOrEmpty
    }
}

Context "Output with -Passthru" {
    It "Returns database object when -Passthru specified" {
        $result = Set-DbaDbState -SqlInstance $TestConfig.instance1 -Database tempdb -ReadOnly -Passthru -EnableException
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'ComputerName'
    }
}
```

### Multiple output types
Create separate contexts for each scenario.

### Collection outputs
Test properties on the first item:
```powershell
$result = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -EnableException
$result[0].PSObject.Properties.Name | Should -Contain 'Name'
```

---

## Execution

1. Read the test file provided
2. Read the corresponding command from public/
3. Analyze output patterns
4. Edit command file to add/update .OUTPUTS if needed
5. Edit test file to add Output Validation context
6. Confirm changes made

**Make the edits directly - do not just output suggestions.**
