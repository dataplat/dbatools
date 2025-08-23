function Resolve-DbaPath {
    <#
    .SYNOPSIS
        Validates and resolves file system paths with enhanced error handling and provider verification.

    .DESCRIPTION
        Validates and resolves file system paths with additional safety checks beyond PowerShell's built-in Resolve-Path cmdlet. This function ensures paths exist and are accessible before performing database operations like backups, restores, or log file management. It provides enhanced error handling, provider validation (FileSystem, Registry, etc.), and supports both existing paths and parent directories for new file creation. DBAs can use this to validate backup destinations, database file locations, and script paths before running maintenance operations, preventing failures due to invalid or inaccessible paths.

    .PARAMETER Path
        The path to validate.

    .PARAMETER Provider
        Ensure the path is of the expected provider.
        Allows ensuring one does not operate in the wrong provider.
        Common providers include the filesystem, the registry or the active directory.

    .PARAMETER SingleItem
        Ensure the path should resolve to a single path only.
        This may - intentionally or not - trip up wildcard paths.

    .PARAMETER NewChild
        Assumes one wishes to create a new child item.
        The parent path will be resolved and must validate true.
        The final leaf will be treated as a leaf item that does not exist yet.

    .NOTES
        Tags: Path, Resolve, Utility
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Resolve-DbaPath

    .EXAMPLE
        PS C:\> Resolve-DbaPath -Path report.log -Provider FileSystem -NewChild -SingleItem

        Ensures the resolved path is a FileSystem path.
        This will resolve to the current folder and the file report.log.
        Will not ensure the file exists or doesn't exist.
        If the current path is in a different provider, it will throw an exception.

    .EXAMPLE
        PS C:\> Resolve-DbaPath -Path ..\*

        This will resolve all items in the parent folder, whatever the current path or drive might be.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]
        $Path,

        [string]
        $Provider,

        [switch]
        $SingleItem,

        [switch]
        $NewChild
    )

    process {
        foreach ($inputPath in $Path) {
            if ($inputPath -eq ".") {
                $inputPath = (Get-Location).Path
            }
            if ($NewChild) {
                $parent = Split-Path -Path $inputPath
                $child = Split-Path -Path $inputPath -Leaf

                try {
                    if (-not $parent) { $parentPath = Get-Location -ErrorAction Stop }
                    else { $parentPath = Resolve-Path $parent -ErrorAction Stop }
                } catch { Stop-Function -Message "Failed to resolve path" -ErrorRecord $_ -EnableException $true }

                if ($SingleItem -and (($parentPath | Measure-Object).Count -gt 1)) {
                    Stop-Function -Message "Could not resolve to a single parent path." -EnableException $true
                }

                if ($Provider -and ($parentPath.Provider.Name -ne $Provider)) {
                    Stop-Function -Message "Resolved provider is $($parentPath.Provider.Name) when it should be $($Provider)" -EnableException $true
                }

                foreach ($parentItem in $parentPath) {
                    Join-Path $parentItem.ProviderPath $child
                }
            } else {
                try { $resolvedPaths = Resolve-Path $inputPath -ErrorAction Stop }
                catch { Stop-Function -Message "Failed to resolve path" -ErrorRecord $_ -EnableException $true }

                if ($SingleItem -and (($resolvedPaths | Measure-Object).Count -gt 1)) {
                    Stop-Function -Message "Could not resolve to a single parent path." -EnableException $true
                }

                if ($Provider -and ($resolvedPaths.Provider.Name -ne $Provider)) {
                    Stop-Function -Message "Resolved provider is $($resolvedPaths.Provider.Name) when it should be $($Provider)" -EnableException $true
                }

                $resolvedPaths.ProviderPath
            }
        }
    }
}