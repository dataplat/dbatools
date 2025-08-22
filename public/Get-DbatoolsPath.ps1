function Get-DbatoolsPath {
    <#
    .SYNOPSIS
        Retrieves configured file paths used by dbatools functions for storing temporary files, logs, and output data.

    .DESCRIPTION
        Retrieves file paths that have been configured for use by dbatools functions. These paths define where the module stores temporary files, exports, logs, and other data during SQL Server operations. DBAs can customize these paths to control where dbatools writes files, ensuring compliance with organizational file storage policies and avoiding permission issues.

        Paths can be configured using Set-DbatoolsPath or directly through the configuration system by creating settings with the format "Path.Managed.<PathName>". Common predefined paths include Temp, LocalAppData, AppData, and ProgramData, but custom paths can be defined for specific workflows like backup file staging or export destinations.

    .PARAMETER Name
        Name of the path to retrieve.

    .NOTES
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbatoolsPath

    .EXAMPLE
        PS C:\> Get-DbatoolsPath -Name 'temp'

        Returns the temp path.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )

    process {
        Get-DbatoolsConfigValue -FullName "Path.Managed.$Name"
    }
}