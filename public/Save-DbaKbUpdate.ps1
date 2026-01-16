function Save-DbaKbUpdate {
    <#
    .SYNOPSIS
        Downloads Microsoft Knowledge Base updates and patches to local storage

    .DESCRIPTION
        Downloads Microsoft KB updates, cumulative updates, and service packs from Microsoft's servers to your local file system. This function handles SQL Server patches as well as any other Microsoft KB updates, making it easy to stage patches for installation across multiple servers. Supports filtering by architecture (x86, x64, ia64) and language, and can download multiple KBs in a single operation. Use this to build a local patch repository or download specific updates for offline installation scenarios.

    .PARAMETER Name
        Specifies the Microsoft Knowledge Base article number to download. Accepts KB prefix or just the numeric value (e.g., 'KB4057119' or '4057119').
        Use this to target specific patches, cumulative updates, or service packs for SQL Server or other Microsoft products.
        Supports multiple KB numbers in a single command for batch downloading.

    .PARAMETER Path
        Specifies the directory where downloaded KB files will be saved. Defaults to the current working directory.
        Use this to organize patches into specific folders or network locations for easier deployment across multiple servers.
        The directory will be created if it doesn't exist.

    .PARAMETER FilePath
        Specifies the exact filename and path for the downloaded file, overriding the server-provided filename.
        Use this when you need custom naming conventions or want to save to a specific location with a particular name.
        Cannot be used when downloading multiple KBs or when Architecture is set to 'All'.

    .PARAMETER Architecture
        Specifies the CPU architecture for the downloaded files. Valid values are 'x64', 'x86', 'ia64', or 'All'.
        Use 'All' to download files for all available architectures when you need to support mixed environments.
        Most modern SQL Server deployments use 'x64', which is the default.

    .PARAMETER Language
        Filters downloads to a specific language version using three-letter language codes (e.g., 'enu' for English, 'deu' for German).
        Primarily useful for SQL Server Service Packs which have separate files per language, unlike Cumulative Updates which are language-neutral.
        Only downloads files matching the specified language code when multiple language versions are available.

    .PARAMETER InputObject
        Accepts pipeline input from Get-DbaKbUpdate, allowing you to filter and select specific files before downloading.
        Use this workflow to preview available downloads with Get-DbaKbUpdate, then pipe selected results for download.
        Particularly useful when working with KBs that have multiple file options.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Deployment, Install, Patching
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Save-DbaKbUpdate

    .OUTPUTS
        System.IO.FileInfo

        Returns one FileInfo object for each successfully downloaded KB file. The objects represent the downloaded files saved to the local file system.

        Properties:
        - Name: The filename of the downloaded KB file
        - FullName: The complete file path where the file was saved
        - Length: The file size in bytes
        - Directory: The directory where the file was saved
        - CreationTime: DateTime when the file was created
        - LastWriteTime: DateTime when the file was last modified
        - Attributes: File attributes (Archive, ReadOnly, Hidden, etc.)
        - Mode: File permissions string (e.g., -a--- for archive)

        Only files that successfully download and exist on disk are returned. If download fails or the file is not found after download, no object is returned for that file.

    .EXAMPLE
        PS C:\> Save-DbaKbUpdate -Name KB4057119

        Downloads KB4057119 to the current directory. This works for SQL Server or any other KB.

    .EXAMPLE
        PS C:\> Get-DbaKbUpdate -Name KB4057119 -Simple | Out-GridView -Passthru | Save-DbaKbUpdate

        Downloads the selected files from KB4057119 to the current directory.

    .EXAMPLE
        PS C:\> Save-DbaKbUpdate -Name KB4057119, 4057114 -Path C:\temp

        Downloads KB4057119 and the x64 version of KB4057114 to C:\temp. This works for SQL Server or any other KB.

    .EXAMPLE
        PS C:\> Save-DbaKbUpdate -Name KB4057114 -Architecture All -Path C:\temp

        Downloads the x64 version of KB4057114 and the x86 version of KB4057114 to C:\temp. This works for SQL Server or any other KB.

    .EXAMPLE
        PS C:\> Save-DbaKbUpdate -Name KB5003279 -Language enu -Path C:\temp

        Downloads only the english version of KB5003279, which is the Service Pack 3 for SQL Server 2016, to C:\temp.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [string]$Path = ".",
        [string]$FilePath,
        [ValidateSet("x64", "x86", "ia64", "All")]
        [string]$Architecture = "x64",
        [string]$Language,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($Name.Count -gt 1 -and $PSBoundParameters.FilePath) {
            Stop-Function -Message "You can only specify one KB when using FilePath"
            return
        }

        if ($Architecture -eq "All" -and $PSBoundParameters.FilePath) {
            Stop-Function -Message "You can only specify one Architecture when using FilePath"
            return
        }

        if (-not $PSBoundParameters.InputObject -and -not $PSBoundParameters.Name) {
            Stop-Function -Message "You must specify a KB name or pipe in results from Get-DbaKbUpdate"
            return
        }

        foreach ($kb in $Name) {
            $InputObject += Get-DbaKbUpdate -Name $kb
        }

        foreach ($link in $InputObject.Link) {
            if ($Architecture -ne "All" -and $link -notmatch "$($Architecture)[-_]") {
                continue
            }
            if ($Language -and $link -notmatch "-$($Language)_") {
                continue
            }

            $fileName = Split-Path -Path $link -Leaf
            if ($PSBoundParameters.FilePath) {
                $file = $FilePath
            } else {
                $file = "$Path$([IO.Path]::DirectorySeparatorChar)$fileName"
            }

            if ((Get-Command Start-BitsTransfer -ErrorAction Ignore)) {
                Start-BitsTransfer -Source $link -Destination $file
            } else {
                Write-Progress -Activity "Downloading $fileName" -Id 1
                Invoke-TlsWebRequest -Uri $link -OutFile $file -ErrorAction Stop
                Write-Progress -Activity "Downloading $fileName" -Id 1 -Completed
            }
            if (Test-Path -Path $file) {
                Get-ChildItem -Path $file
            }
        }
    }
}