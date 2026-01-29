# Command Specification: <Verb>-Dba<Noun>

## Overview

**Command Name**: `<Verb>-Dba<Noun>`
**Author**: the dbatools team + Claude
**Category**: <Category: Database, Server, Security, Agent, etc.>

### Purpose
<!-- One paragraph describing what this command does and why users need it -->

### User Stories
<!-- Who uses this command and what do they accomplish? -->

- As a DBA, I want to ... so that ...
- As a developer, I want to ... so that ...

---

## Requirements

### Functional Requirements

1. **Core Functionality**
   - [ ] Requirement 1
   - [ ] Requirement 2

2. **Input Handling**
   - [ ] Accept SqlInstance parameter (single or array)
   - [ ] Support pipeline input from `<related command>`
   - [ ] Handle SqlCredential for authentication

3. **Output**
   - [ ] Emit objects immediately to pipeline (no collection)
   - [ ] Include standard properties: ComputerName, InstanceName, SqlInstance
   - [ ] Custom type name: `Sqlcollaborative.Dbatools.<TypeName>`

### Non-Functional Requirements

- **SQL Server Compatibility**: Minimum version SQL Server <2000|2005|2008|2012|etc.>
- **PowerShell Compatibility**: PowerShell v3+
- **Performance**: Should handle <N> objects efficiently

---

## Technical Design

### Approach
<!-- SMO-first or T-SQL? Explain the choice -->

- [ ] Use SMO for: <describe>
- [ ] Use T-SQL for: <describe if needed>

### Similar Commands
<!-- Reference existing dbatools commands to follow as patterns -->

- `Get-DbaXxx` - Similar pattern for <reason>
- `Set-DbaYyy` - Reference for <reason>

### Parameters

| Parameter | Type | Mandatory | Pipeline | Description |
|-----------|------|-----------|----------|-------------|
| SqlInstance | DbaInstanceParameter[] | Yes | No | Target SQL Server instance(s) |
| SqlCredential | PSCredential | No | No | SQL Server authentication credential |
| EnableException | Switch | No | No | Throw terminating errors |
| <CustomParam> | <Type> | <Yes/No> | <Yes/No> | <Description> |

### Output Object

```powershell
[PSCustomObject]@{
    ComputerName   = $server.ComputerName
    InstanceName   = $server.ServiceName
    SqlInstance    = $server.DomainInstanceName
    # Add command-specific properties
}
```

---

## Test Scenarios

### Unit Tests

1. **Parameter Validation**
   - Test: All mandatory parameters are required
   - Test: SqlInstance accepts array input

2. **Core Functionality**
   - Test: <describe test scenario>
   - Test: <describe test scenario>

### Integration Tests

1. **Single Instance**
   - Test against: `$TestConfig.instance1`
   - Expected: <describe expected outcome>

2. **Multiple Instances**
   - Test against: `$TestConfig.instance1`, `$TestConfig.instance2`
   - Expected: <describe expected outcome>

3. **Pipeline Input**
   - Test: Pipe from `<source command>` | `<this command>`
   - Expected: <describe expected outcome>

---

## Edge Cases and Error Handling

| Scenario | Expected Behavior |
|----------|-------------------|
| SQL Server version too old | Skip with warning (unless EnableException) |
| Object not found | Return nothing (or warning based on pattern) |
| Permission denied | Write warning with details |
| Connection failure | Standard dbatools connection error handling |

---

## Implementation Notes

### Files to Create/Modify

1. `public/<Verb>-Dba<Noun>.ps1` - Main command implementation
2. `tests/<Verb>-Dba<Noun>.Tests.ps1` - Pester v5 tests
3. `dbatools.psd1` - Add to FunctionsToExport
4. `dbatools.psm1` - Add to Export-ModuleMember

### Dependencies

- Existing dbatools functions: `<list>`
- SMO classes: `<list>`
- .NET types: `<list>`

### Code Pattern Reference

```powershell
# Use this pattern for the main processing loop
foreach ($instance in $SqlInstance) {
    try {
        $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
    } catch {
        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $instance -Continue
    }

    # Process and emit objects immediately
    foreach ($item in $collection) {
        [PSCustomObject]@{
            ComputerName = $server.ComputerName
            # ... properties
        }
    }
}
```

---

## Acceptance Criteria

- [ ] Command follows dbatools naming conventions
- [ ] All parameters use proper types (no `= $true` syntax)
- [ ] Uses splatting for 3+ parameter calls
- [ ] Emits objects immediately to pipeline
- [ ] Includes proper help documentation
- [ ] Has Pester v5 tests with >80% coverage
- [ ] Registered in both dbatools.psd1 and dbatools.psm1
- [ ] Works with SQL Server <minimum version>+
- [ ] No backticks for line continuation
- [ ] Hashtables are properly aligned
