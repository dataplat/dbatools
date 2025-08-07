# Style Guidelines

## Formatting Rules
- Use double quotes for strings (we're a SQL Server module)
- Array declarations should be on multiple lines:
```powershell
$array = @(
    "Item1",
    "Item2",
    "Item3"
)
```
- Skip conditions must evaluate to `$true` or `$false`, not strings
- Use `$global:` instead of `$script:` for test configuration variables when required for Pester v5 scoping
- No trailing spaces
- Use `$results.PropertyX.Count` for accurate counting vs $results.Count

## Where-Object Usage
Avoid script blocks in Where-Object when possible:
```powershell
# Good - direct property comparison
$master    = $databases | Where-Object Name -eq "master"
$systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"

# Required - script block for Parameters.Keys or filtering
$hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ('WhatIf', 'Confirm') }
```