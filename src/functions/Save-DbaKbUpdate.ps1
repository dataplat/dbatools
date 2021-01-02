function Save-DbaKbUpdate {
    <#
    .SYNOPSIS
        Downloads patches from Microsoft

    .DESCRIPTION
         Downloads patches from Microsoft

    .PARAMETER Name
        The KB name or number. For example, KB4057119 or 4057119.

    .PARAMETER Path
        The directory to save the file.

    .PARAMETER FilePath
        The exact file name to save to, otherwise, it uses the name given by the webserver

     .PARAMETER Architecture
        Defaults to x64. Can be x64, x86, ia64 or "All"

    .PARAMETER InputObject
        Enables piping from Get-DbaKbUpdate

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Update, Patching, Install
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Save-DbaKbUpdate

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
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [string]$Path = ".",
        [string]$FilePath,
        [ValidateSet("x64", "x86", "ia64", "All")]
        [string]$Architecture = "x64",
        [parameter(ValueFromPipeline)]
        [pscustomobject]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($Name.Count -gt 0 -and $PSBoundParameters.FilePath) {
            Stop-Function -Message "You can only specify one KB when using FilePath"
            return
        }

        if (-not $PSBoundParameters.InputObject -and -not $PSBoundParameters.Name) {
            Stop-Function -Message "You must specify a KB name or pipe in results from Get-DbaKbUpdate"
            return
        }

        foreach ($kb in $Name) {
            $InputObject += Get-DbaKbUpdate -Name $kb
        }

        foreach ($item in $InputObject.Link) {
            if ($item.Count -gt 1 -and $Architecture -ne "All") {
                $templinks = $item | Where-Object { $PSItem -match "$($Architecture)_" }
                if ($templinks) {
                    $item = $templinks
                } else {
                    Write-Message -Level Warning -Message "Could not find architecture match, downloading all"
                }
            }

            foreach ($link in $item) {
                if (-not $PSBoundParameters.FilePath) {
                    $FilePath = Split-Path -Path $link -Leaf
                } else {
                    $Path = Split-Path -Path $FilePath
                }

                $file = "$Path$([IO.Path]::DirectorySeparatorChar)$FilePath"

                if ((Get-Command Start-BitsTransfer -ErrorAction Ignore)) {
                    Start-BitsTransfer -Source $link -Destination $file
                } else {
                    # IWR is crazy slow for large downloads
                    $currentVersionTls = [Net.ServicePointManager]::SecurityProtocol
                    $currentSupportableTls = [Math]::Max($currentVersionTls.value__, [Net.SecurityProtocolType]::Tls.value__)
                    $availableTls = [enum]::GetValues('Net.SecurityProtocolType') | Where-Object { $_ -gt $currentSupportableTls }
                    $availableTls | ForEach-Object {
                        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor $_
                    }

                    Write-Progress -Activity "Downloading $FilePath" -Id 1
                    (New-Object Net.WebClient).DownloadFile($link, $file)
                    Write-Progress -Activity "Downloading $FilePath" -Id 1 -Completed


                    [Net.ServicePointManager]::SecurityProtocol = $currentVersionTls
                }
                if (Test-Path -Path $file) {
                    Get-ChildItem -Path $file
                }
            }
        }
    }
}
