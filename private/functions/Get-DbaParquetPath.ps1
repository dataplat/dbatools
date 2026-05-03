function Get-DbaParquetPath {
    <#
    .SYNOPSIS
        Gets the path to the Parquet.NET assembly.

    .DESCRIPTION
        Finds the Parquet.NET assembly used by Import-DbaParquet. Checks the currently loaded assembly first,
        then the dbatools data directory populated by Install-DbaParquet, then the legacy bundled module path.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Parquet, Import
        Author: dbatools team

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        System.String. The path to the Parquet.NET assembly if found, otherwise $null.
    #>
    [CmdletBinding()]
    param (
        [switch]$Silent,
        [switch]$EnableException
    )

    $loadedAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq "Parquet" } | Select-Object -First 1
    if ($loadedAssembly -and $loadedAssembly.Location -and (Test-Path -Path $loadedAssembly.Location)) {
        Write-Message -Level Verbose -Message "Found loaded Parquet.NET assembly at: $($loadedAssembly.Location)"
        return $loadedAssembly.Location
    }

    $searchPaths = @()

    $configuredPath = Get-DbatoolsConfigValue -FullName "Path.DbatoolsParquet"
    if ($configuredPath) {
        $configuredPath = $configuredPath.TrimEnd("/", "\")
        $searchPaths += Join-Path -Path $configuredPath -ChildPath "Parquet.dll"
        $searchPaths += Join-Path -Path $configuredPath -ChildPath "Parquet.Net.dll"
    }

    $dbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"
    if ($dbatoolsData) {
        $dbatoolsData = $dbatoolsData.TrimEnd("/", "\")
        $searchPaths += Join-Path -Path $dbatoolsData -ChildPath "parquet" | Join-Path -ChildPath "Parquet.dll"
        $searchPaths += Join-Path -Path $dbatoolsData -ChildPath "parquet" | Join-Path -ChildPath "Parquet.Net.dll"
    }

    if ($script:PSModuleRoot) {
        $searchPaths += Join-Path -Path $script:PSModuleRoot -ChildPath "bin" | Join-Path -ChildPath "parquet" | Join-Path -ChildPath "Parquet.dll"
        $searchPaths += Join-Path -Path $script:PSModuleRoot -ChildPath "bin" | Join-Path -ChildPath "parquet" | Join-Path -ChildPath "Parquet.Net.dll"
    }

    foreach ($path in $searchPaths) {
        if (Test-Path -Path $path) {
            Write-Message -Level Verbose -Message "Found Parquet.NET assembly at: $path"
            return $path
        }
    }

    $message = @"
Could not find Parquet.NET. Parquet.NET is required for Import-DbaParquet.

To install Parquet.NET, use:
    Install-DbaParquet

This will download Parquet.NET and its managed dependencies to your dbatools data directory.
"@

    if ($Silent) {
        return $null
    }

    Stop-Function -Message $message -Target "Parquet.NET"
    if ($EnableException) {
        throw "Parquet.NET not found"
    }
    return $null
}
