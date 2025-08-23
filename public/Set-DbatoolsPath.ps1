function Set-DbatoolsPath {
    <#
    .SYNOPSIS
        Configures or updates a path under a name.

    .DESCRIPTION
        Configures or updates a path under a name.
        The path can be persisted using the "-Register" command.
        Paths setup like this can be retrieved using Get-DbatoolsPath.

    .PARAMETER Name
        Specifies the alias name to associate with the path for easy retrieval.
        Use descriptive names like 'backups', 'scripts', or 'logs' to organize commonly used directory paths.
        The name can be referenced later with Get-DbatoolsPath to quickly access the stored path.

    .PARAMETER Path
        Specifies the directory path to store under the given name.
        Can be any valid file system path including network shares and mapped drives.
        Use this to centralize path management for backup locations, script directories, or output folders.

    .PARAMETER Register
        Persists the path configuration across PowerShell sessions and module reloads.
        Without this switch, the path mapping only exists for the current session.
        Essential when setting up permanent path aliases for team environments or automated scripts.

    .PARAMETER Scope
        Determines where the persistent configuration is stored when using -Register.
        UserDefault stores the setting for the current user only, while other scopes affect system-wide or module-level settings.
        Choose the appropriate scope based on whether the path should be available to all users or just the current user.

    .LINK
        https://dbatools.io/Set-DbatoolsPath

    .EXAMPLE
        PS C:\> Set-DbatoolsPath -Name 'temp' -Path 'C:\temp'

        Configures C:\temp as the current temp path. (does not override $Env:TEMP !)
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
        [Dataplat.Dbatools.Configuration.ConfigScope]
        $Scope = [Dataplat.Dbatools.Configuration.ConfigScope]::UserDefault
    )

    process {
        Set-DbatoolsConfig -FullName "Path.Managed.$Name" -Value $Path
        if ($Register) { Register-DbatoolsConfig -FullName "Path.Managed.$Name" -Scope $Scope }
    }
}