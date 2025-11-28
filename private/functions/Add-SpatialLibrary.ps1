function Add-SpatialLibrary {
    <#
    .SYNOPSIS
        Loads the Microsoft.SqlServer.Types assembly for spatial data type support.

    .DESCRIPTION
        Loads the Microsoft.SqlServer.Types.dll assembly which contains SqlGeography and SqlGeometry types.
        This is required for bulk copy operations on tables with spatial data types.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Internal
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
    #>
    [CmdletBinding()]
    param(
        [switch]$EnableException
    )
    try {
        $platformlib = Join-DbaPath -Path $script:libraryroot -ChildPath lib
        $typesdll = Join-DbaPath -Path $platformlib -ChildPath Microsoft.SqlServer.Types.dll
        Add-Type -Path $typesdll -ErrorAction Stop
        Write-Message -Level Verbose -Message "Loaded Microsoft.SqlServer.Types assembly for spatial data type support"
    } catch {
        $message = "Could not load Microsoft.SqlServer.Types assembly. Spatial data types (Geography, Geometry) will not be supported in bulk copy operations. Error: $($PSItem.Exception.Message)"
        if ($EnableException) {
            Stop-Function -Message $message -ErrorRecord $PSItem
        } else {
            Write-Message -Level Warning -Message $message
        }
        return
    }
}
