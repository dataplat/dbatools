function Get-DbaParquetEditionFolder {
    <#
    .SYNOPSIS
        Gets the name of the Parquet.NET installation subfolder for the running PowerShell edition.

    .DESCRIPTION
        Install-DbaParquet picks the Parquet.NET assemblies that match the runtime it is running on:
        .NET Framework targets on Windows PowerShell and net<major> targets on PowerShell 7. Both
        editions share one dbatools data directory, so the assemblies have to live in a folder per
        edition. Without that, whichever edition installs last leaves assemblies the other one cannot
        load, and every import fails there with a type load error that looks like a broken install.

    .NOTES
        Tags: Parquet, Import
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        System.String. The subfolder name, either "core" or "desktop".
    #>
    [CmdletBinding()]
    param ()

    # PSEdition does not exist on PowerShell 3 and 4, and those are always Desktop.
    if ($PSVersionTable.PSEdition -eq "Core") {
        return "core"
    }

    return "desktop"
}
