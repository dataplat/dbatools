<#

	Attempt to load all versions of SMO from vNext to 2005 - this is why RequiredAssemblies can't be used.

	Attempt to load all assemblies that will be needed in the module. 

	Not all versions support supporting assemblies, so ignore and let the command catch it.

	This takes about 11ms on a newer machine.

#>

$smoversions = "14.0.0.0", "13.0.0.0", "12.0.0.0", "11.0.0.0", "10.0.0.0", "9.0.242.0", "9.0.0.0"

foreach ($smoversion in $smoversions)
{
    try
    {
        Add-Type -AssemblyName "Microsoft.SqlServer.Smo, Version=$smoversion, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop
        $smoadded = $true
    }
    catch
    {
        $smoadded = $false
    }
    
    if ($smoadded -eq $true) { break }
}

if ($smoadded -eq $false) { throw "Can't load SMO assemblies. You must have SQL Server Management Studio installed to proceed." }

$assemblies = "Management.Common", "Dmf", "Instapi", "SqlWmiManagement", "ConnectionInfo", "SmoExtended", "SqlTDiagM", "Management.Utility",
"SString", "Management.RegisteredServers", "Management.Sdk.Sfc", "SqlEnum", "RegSvrEnum", "WmiEnum", "ServiceBrokerEnum", "Management.XEvent",
"ConnectionInfoExtended", "Management.Collector", "Management.CollectorEnum", "Management.Dac", "Management.DacEnum", "Management.IntegrationServices"

foreach ($assembly in $assemblies)
{
    try
    {
        Add-Type -AssemblyName "Microsoft.SqlServer.$assembly, Version=$smoversion, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop
    }
    catch
    {
        # Don't care
    }
}

<# 

	Do the rest of the loading 

#>

# This technique helps a little bit
# https://becomelotr.wordpress.com/2017/02/13/expensive-dot-sourcing/

# Load our own custom library
# Should always come before function imports
. ([scriptblock]::Create([io.file]::ReadAllText("$PSScriptRoot\bin\library.ps1")))

# All internal functions privately available within the toolset
foreach ($function in (Get-ChildItem "$PSScriptRoot\internal\*.ps1"))
{
	. ([scriptblock]::Create([io.file]::ReadAllText($function)))
}

# All exported functions
foreach ($function in (Get-ChildItem "$PSScriptRoot\functions\*.ps1"))
{
	. ([scriptblock]::Create([io.file]::ReadAllText($function)))
}

# Run all optional code
# Note: Each optional file must include a conditional governing whether it's run at all.
# Validations were moved into the other files, in order to prevent having to update dbatools.psm1 every time
foreach ($function in (Get-ChildItem "$PSScriptRoot\optional\*.ps1"))
{
    . ([scriptblock]::Create([io.file]::ReadAllText($function)))
}

#region Finally register autocompletion
# Test whether we have Tab Expansion Plus available (used in dynamicparams scripts ran below)
if (Get-Command TabExpansionPlusPlus\Register-ArgumentCompleter -ErrorAction Ignore)
{
    $TEPP = $true
}
else
{
    $TEPP = $false
}

foreach ($function in (Get-ChildItem "$PSScriptRoot\internal\dynamicparams\*.ps1"))
{
	. ([scriptblock]::Create([io.file]::ReadAllText($function)))
}
#endregion Finally register autocompletion

# Load configuration system
# Should always go next to last
. ([scriptblock]::Create([io.file]::ReadAllText("$PSScriptRoot\internal\configurations\configuration.ps1")))

# Load scripts that must be individually run at the end #
#-------------------------------------------------------#

# Start the logging system (requires the configuration system up and running)
. ([scriptblock]::Create([io.file]::ReadAllText("$PSScriptRoot\internal\scripts\logfilescript.ps1")))

# Not supporting the provider path at this time
# if (((Resolve-Path .\).Path).StartsWith("SQLSERVER:\")) { throw "Please change to another drive and reload the module." }

# I renamed this function to be more accurate
Set-Alias -Name Reset-SqlSaPassword -Value Reset-SqlAdmin
Set-Alias -Name Copy-SqlUserDefinedMessage -Value Copy-SqlCustomError
Set-Alias -Name Copy-SqlJobServer -Value Copy-SqlServerAgent
Set-Alias -Name Restore-HallengrenBackup -Value Restore-SqlBackupFromDirectory
Set-Alias -Name Show-SqlMigrationConstraint -Value Test-SqlMigrationConstraint
Set-Alias -Name Test-SqlDiskAllocation -Value Test-DbaDiskAllocation
Set-Alias -Name Get-DiskSpace -Value Get-DbaDiskSpace
Set-Alias -Name Get-SqlMaxMemory -Value Get-DbaMaxMemory
Set-Alias -Name Set-SqlMaxMemory -Value Set-DbaMaxMemory