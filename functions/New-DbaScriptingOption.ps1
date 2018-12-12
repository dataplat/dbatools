function New-DbaScriptingOption {
    <#
    .SYNOPSIS
        Creates a new Microsoft.SqlServer.Management.Smo.ScriptingOptions object

    .DESCRIPTION
        Creates a new Microsoft.SqlServer.Management.Smo.ScriptingOptions object. Basically saves you the time from remembering the SMO assembly name ;)

        See https://msdn.microsoft.com/en-us/library/microsoft.sqlserver.management.smo.scriptingoptions.aspx for more information

    .NOTES
        Tags: Migration, Backup, DR
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaScriptingOption

    .EXAMPLE
        PS C:\> $options = New-DbaScriptingOption
        PS C:\> $options.ScriptDrops = $false
        PS C:\> $options.WithDependencies = $true
        PS C:\> Get-DbaAgentJob -SqlInstance sql2016 | Export-DbaScript -ScriptingOptionObject $options

        Exports Agent Jobs with the Scripting Options ScriptDrops set to $false and WithDependencies set to true

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    param()
    New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
}