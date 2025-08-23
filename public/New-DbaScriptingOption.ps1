function New-DbaScriptingOption {
    <#
    .SYNOPSIS
        Creates a customizable SMO ScriptingOptions object for controlling T-SQL script generation

    .DESCRIPTION
        Creates a Microsoft.SqlServer.Management.Smo.ScriptingOptions object that controls how SQL Server objects get scripted into T-SQL CREATE statements. This object lets you customize what gets included when using Export-DbaScript and other dbatools scripting commands - things like whether to include indexes, triggers, permissions, dependencies, or batch separators. Perfect for creating deployment scripts where you need specific control over what gets scripted and how it's formatted.

        See https://msdn.microsoft.com/en-us/library/microsoft.sqlserver.management.smo.scriptingoptions.aspx for more information

    .NOTES
        Tags: General, Script, Object
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaScriptingOption

    .EXAMPLE
        PS C:\> $options = New-DbaScriptingOption
        PS C:\> $options.ScriptDrops = $false
        PS C:\> $options.WithDependencies = $false
        PS C:\> $options.AgentAlertJob = $true
        PS C:\> $options.AgentNotify = $true
        PS C:\> Get-DbaAgentJob -SqlInstance sql2016 | Export-DbaScript -ScriptingOptionObject $options

        Exports Agent Jobs with the Scripting Options ScriptDrops/WithDependencies set to $false and AgentAlertJob/AgentNotify set to true

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    param()
    New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
}