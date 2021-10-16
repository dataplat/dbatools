function Set-DbatoolsPath {
    <#
    .SYNOPSIS
        Configures or updates a path under a name.

    .DESCRIPTION
        Configures or updates a path under a name.
        The path can be persisted using the "-Register" command.
        Paths setup like this can be retrieved using Get-DbatoolsPath.

    .PARAMETER Name
        Name the path should be stored under.

    .PARAMETER Path
        The path that should be returned under the name.

    .PARAMETER Register
        Registering a path in order for it to persist across sessions.

    .PARAMETER Scope
        The configuration scope it should be registered under.
        Defaults to UserDefault.
        Configuration scopes are the default locations configurations are being stored at.

    .LINK
        https://dbatools.io/Set-DbatoolsPath

    .EXAMPLE
        PS C:\> Set-DbatoolsPath -Name 'temp' -Path 'C:\temp'

        Configures C:\temp as the current temp path. (does not override $env:temp !)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(ParameterSetName = 'Register', Mandatory = $true)]
        [switch]$Register,
        [Parameter(ParameterSetName = 'Register')]
        [Sqlcollaborative.Dbatools.Configuration.ConfigScope]
        $Scope = [Sqlcollaborative.Dbatools.Configuration.ConfigScope]::UserDefault
    )

    process {
        Set-DbatoolsConfig -FullName "Path.Managed.$Name" -Value $Path
        if ($Register) { Register-DbatoolsConfig -FullName "Path.Managed.$Name" -Scope $Scope }
    }
}