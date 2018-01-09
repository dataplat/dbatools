function New-DbaScriptingOption {
    <#
    .SYNOPSIS
    Creates a new Microsoft.SqlServer.Management.Smo.ScriptingOptions object

    .DESCRIPTION
    Creates a new Microsoft.SqlServer.Management.Smo.ScriptingOptions object. Basically saves you the time from remembering the SMO assembly name ;)

    See https://msdn.microsoft.com/en-us/library/microsoft.sqlserver.management.smo.scriptingoptions.aspx for more information

    .NOTES
    Tags: Migration, Backup, DR

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/New-DbaScriptingOption
    https://msdn.microsoft.com/en-us/library/microsoft.sqlserver.management.smo.scriptingoptions.aspx

    .EXAMPLE
    $options = New-DbaScriptingOption
    $options.ScriptDrops = $false
    $options.WithDependencies = $true
    Get-DbaAgentJob -SqlInstance sql2016 | Export-DbaScript -ScriptingOptionObject $options

    Exports Agent Jobs with the Scripting Options ScriptDrops set to $false and WithDependencies set to true

    #>
    New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
}