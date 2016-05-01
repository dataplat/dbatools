# All supporting functions have been moved to Functions\SharedFunctions.ps1
# If you're looking through the code, you pretty much have to work with two files
# at any one time. The function you're working on, and SharedFunctions.ps1
foreach ($function in (Get-ChildItem "$PSScriptRoot\Functions\*.ps1")) { . $function }

# Not supporting the provider path at this time
if (((Resolve-Path .\).Path).StartsWith("SQLSERVER:\")) { throw "Starting " }

# I renamed this function to be more accurate
Set-Alias -Name Reset-SqlSaPassword -Value Reset-SqlAdmin

# Strictmode coming when I've got time.
# Set-StrictMode -Version Latest