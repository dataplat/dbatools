function Join-DbaPath {
    <#
    .SYNOPSIS
        Constructs file paths with correct separators for Windows and Linux SQL Server instances.

    .DESCRIPTION
        Constructs file paths by joining multiple segments while automatically using the correct path separators (backslash for Windows, forward slash for Linux) based on the target SQL Server instance's operating system. This function eliminates the guesswork when building file paths for backup files, exports, scripts, or other SQL Server operations that need to reference files on the remote server. Without specifying a SqlInstance, it defaults to the local machine's path separator conventions.

    .PARAMETER Path
        Specifies the base directory path where backup files, scripts, or other SQL Server resources will be stored. This forms the root location for building complete file paths.
        Use this when you need to define the starting directory for backup operations, export locations, or script file destinations on either local or remote SQL Server instances.

    .PARAMETER SqlInstance
        Optional -- tests to see if destination SQL Server is Linux or Windows

    .PARAMETER Child
        Specifies additional path segments to append to the base path, such as subdirectories, filename prefixes, or date folders. Accepts multiple values to build nested directory structures.
        Use this to organize files into logical groupings like database names, backup types, or date-based folders (e.g., 'MyDatabase', 'Full', '2024-01-15').

    .NOTES
        Tags: Path, Utility
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Join-DbaPath

    .EXAMPLE
        PS C:\> Join-DbaPath -Path 'C:\temp' 'Foo' 'Bar'

        Returns 'C:\temp\Foo\Bar' on windows.
        Returns 'C:/temp/Foo/Bar' on non-windows.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,
        [DbaInstanceParameter]$SqlInstance,
        [Parameter(ValueFromRemainingArguments)]
        [Alias("ChildPath")]
        [string[]]$Child
    )

    if (-not $SqlInstance) {
        return @($path) + $Child -join
        [IO.Path]::DirectorySeparatorChar -replace
        '\\|/', [IO.Path]::DirectorySeparatorChar
    }

    $resultingPath = $Path

    if (Test-HostOSLinux -SqlInstance $SqlInstance) {
        Write-Message -Level Verbose -Message "Linux detected on remote server"
        $resultingPath = $resultingPath.Replace("\", "/")

        foreach ($childItem in $Child) {
            $resultingPath = ($resultingPath, $childItem) -join '/'
        }
    } else {
        if (($PSVersionTable.PSVersion.Major -ge 6) -and (-not $script:isWindows)) {
            $resultingPath = $resultingPath.Replace("\", "/")
        } else {
            $resultingPath = $resultingPath.Replace("/", "\")
        }

        foreach ($childItem in $Child) {
            $resultingPath = [IO.Path]::Combine($resultingPath, $childItem)
        }
    }

    $resultingPath
}