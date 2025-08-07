# PowerShell Syntax Requirements Directive

## VARIABLE REFERENCES

Replace all `$_` with `$PSItem` except where `$_` is required for compatibility.

Preserve all parameter names exactly as written in original tests without modification.

## WHERE-OBJECT CONVERSION

Transform Where-Object script blocks to direct property comparisons when possible:

```powershell
# Good - direct property comparison
$master    = $databases | Where-Object Name -eq "master"
$systemDbs = $databases | Where-Object Name -in "master", "model", "msdb", "tempdb"

# Required - script block for Parameters.Keys or filtering
$hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ('WhatIf', 'Confirm') }
```

## STRING FORMATTING

Convert all single quotes to double quotes for string literals.

Add proper quote escaping when needed.

Replace multi-line concatenated strings with here-strings when appropriate.

## SCOPE DECLARATIONS

Replace all `$script:` with `$global:` for test configuration variables (Pester v5 scoping requirement).

Add explicit scope declarations when variables cross Pester block boundaries.

## ARRAY OPERATIONS

Replace `$results.Count` with `$results.Status.Count` for accurate counting.

Add explicit array initialization: `$array = @()`.

Wrap result collection in array subexpression operator: `$results = @(Get-Something)`.

## PARAMETER QUOTING

Remove unnecessary quotes from parameter values:

```powershell
# Convert this:
"$CommandName" -Tag "IntegrationTests"
# To this:
$CommandName -Tag IntegrationTests
```

## CODE FORMATTING

Apply OTBS (One True Brace Style) formatting to all code blocks.