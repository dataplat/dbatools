function Update-DbaBuildReference {
    <#
    .SYNOPSIS
        Downloads the latest SQL Server build reference database used for patch compliance and version tracking

    .DESCRIPTION
        Refreshes the comprehensive SQL Server build reference database that powers Get-DbaBuild and Test-DbaBuild functions with current patch level information. This database contains detailed mappings between build numbers, service packs, cumulative updates, KB articles, release dates, and support lifecycle dates for all SQL Server versions.

        DBAs use this to maintain accurate patch compliance reporting and identify outdated installations that need security updates. The function downloads the latest reference data from the dbatools project repository, ensuring you have current information about newly released patches and updated support timelines.

        The reference file is stored locally and automatically updated from newer module versions, but this command ensures you get the very latest patch data between dbatools releases. You can also specify a local file path instead of downloading, useful for air-gapped environments.

        Use Get-DbatoolsConfigValue -Name 'assets.sqlbuildreference' to see the current download URL.

    .PARAMETER LocalFile
        Specifies the path to a local JSON build reference file to use instead of downloading from the internet.
        Use this in air-gapped environments or when you need to use a specific version of the build reference data.
        The file must be the dbatools-buildref-index.json format containing SQL Server build mappings and patch information.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        None

        This function does not return pipeline objects. It updates the local build reference database file and provides informational messages via Write-Message at the Output level to indicate successful updates.

        The function modifies files on disk:
        - If the reference file needs updating, it writes the new version to the writable location (typically in the dbatools data directory)
        - Messages are written to indicate the update timestamp comparison and result

        To track the update result, capture Write-Message output or monitor the exit status of the command.

    .NOTES
        Tags: Utility, SqlBuild
        Author: Simone Bizzotto (@niphold) | Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Update-DbaBuildReference

    .EXAMPLE
        PS C:\> Update-DbaBuildReference

        Looks online if there is a newer version of the build reference

    .EXAMPLE
        PS C:\> Update-DbaBuildReference -LocalFile \\fileserver\Software\dbatools\dbatools-buildref-index.json

        Uses the given file instead of downloading the file to update the build reference

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(DefaultParameterSetName = 'Build')]
    param (
        [string]$LocalFile,
        [switch]$EnableException
    )

    begin {
        function Get-DbaBuildReferenceIndexOnline {
            [CmdletBinding()]
            param (
                [bool]
                $EnableException
            )
            $url = Get-DbatoolsConfigValue -Name 'assets.sqlbuildreference'
            try {
                $webContent = Invoke-TlsWebRequest $url -UseBasicParsing -ErrorAction Stop
            } catch {
                try {
                    Write-Message -Level Verbose -Message "Probably using a proxy for internet access, trying default proxy settings"
                    (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                    $webContent = Invoke-TlsWebRequest $url -UseBasicParsing -ErrorAction Stop
                } catch {
                    Write-Message -Level Warning -Message "Couldn't download updated index from $url"
                    return
                }
            }
            return $webContent.Content
        }

    }
    process {
        $Moduledirectory = $script:PSModuleRoot
        $orig_idxfile = Resolve-Path "$Moduledirectory\bin\dbatools-buildref-index.json"
        $DbatoolsData = Get-DbatoolsConfigValue -Name 'Path.DbatoolsData'
        $writable_idxfile = Join-Path $DbatoolsData "dbatools-buildref-index.json"

        if (-not (Test-Path $orig_idxfile)) {
            Write-Message -Level Warning -Message "Unable to read local SQL build reference file. Please check your module integrity or reinstall dbatools."
        }

        if ((-not (Test-Path $orig_idxfile)) -and (-not (Test-Path $writable_idxfile))) {
            throw "Build reference file not found, please check module health."
        }

        # If no writable copy exists, create one and return the module original
        if (-not (Test-Path $writable_idxfile)) {
            Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
            $offline_time = Get-Date (Get-Content $orig_idxfile -Raw | ConvertFrom-Json).LastUpdated
        }

        # Else, if both exist, update the writeable if necessary and return the current version
        elseif (Test-Path $orig_idxfile) {
            $module_content = Get-Content $orig_idxfile -Raw | ConvertFrom-Json
            $data_content = Get-Content $writable_idxfile -Raw | ConvertFrom-Json

            $module_time = Get-Date $module_content.LastUpdated
            $data_time = Get-Date $data_content.LastUpdated

            $offline_time = $module_time
            if ($module_time -gt $data_time) {
                Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
            } else {
                $offline_time = $data_time
            }
        }

        # Depending on LocalFile, use file or internet as source
        if ($LocalFile) {
            try {
                $newContent = Get-Content -Path $LocalFile
            } catch {
                Stop-Function -Message "Unable to read content from $LocalFile"
            }
        } else {
            $newContent = Get-DbaBuildReferenceIndexOnline -EnableException $EnableException
        }

        # If new data was sucessful read, compare LastUpdated and copy if newer
        if ($null -ne $newContent) {
            $new_time = Get-Date ($newContent | ConvertFrom-Json).LastUpdated
            if ($new_time -gt $offline_time) {
                Write-Message -Level Output -Message "Index updated correctly, last update on: $(Get-Date -Date $new_time -Format s), was $(Get-Date -Date $offline_time -Format s)"
                $newContent | Out-File $writable_idxfile -Encoding utf8 -ErrorAction Stop
            }
        }

    }
}