# PowerShell Syntax Requirements

## Syntax Requirements
- Use $PSItem instead of $_ (except where $_ is required for compatibility)
- Match parameter names from original tests exactly

## Where-Object Usage
Avoid script blocks in Where-Object when possible:
```powershell
# Good - direct property comparison
$master    = $databases | Where-Object Name -eq "master"
$systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"

# Required - script block for Parameters.Keys or filtering
$hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ('WhatIf', 'Confirm') }
```

## String Handling
- Use double quotes for strings (we're a SQL Server module)
- Escape quotes properly when needed
- Use here-strings for multi-line strings when appropriate

## Variable Scope
- Use `$global:` instead of `$script:` for test configuration variables when required for Pester v5 scoping
- Be explicit about variable scope when crossing Pester block boundaries

## Array Handling
- Use `$results.Status.Count` for accurate counting
- Initialize arrays explicitly: `$array = @()`
- Use array subexpression operator when collecting results: `$results = @(Get-Something)`