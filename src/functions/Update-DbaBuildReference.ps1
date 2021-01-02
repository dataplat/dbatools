function Update-DbaBuildReference {
    <#
    .SYNOPSIS
        Updates the local reference looking online for the most up to date.

    .DESCRIPTION
        This function updates the local json files containing all the infos about SQL builds.
        It uses the setting 'assets.sqlbuildreference' to fetch it.
        To see your current setting, use Get-DbatoolsConfigValue -Name 'assets.sqlbuildreference'

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SqlBuild
        Author: Simone Bizzotto (@niphold) | Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Update-DbaBuildReference

    .EXAMPLE
        PS C:\> Update-DbaBuildReference

        Looks online if there is a newer version of the build reference

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(DefaultParameterSetName = 'Build')]
    param (
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
                $WebContent = Invoke-TlsWebRequest $url -UseBasicParsing -ErrorAction Stop
            } catch {
                try {
                    Write-Message -Level Verbose -Message "Probably using a proxy for internet access, trying default proxy settings"
                    (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                    $WebContent = Invoke-TlsWebRequest $url -UseBasicParsing -ErrorAction Stop
                } catch {
                    Write-Message -Level Warning -Message "Couldn't download updated index from $url"
                    return
                }
            }
            return $WebContent
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
        $WebContent = Get-DbaBuildReferenceIndexOnline -EnableException $EnableException
        if ($null -ne $WebContent) {
            $webdata_content = $WebContent.Content | ConvertFrom-Json
            $webdata_time = Get-Date $webdata_content.LastUpdated
            if ($webdata_time -gt $offline_time) {
                Write-Message -Level Output -Message "Index updated correctly, last update on: $(Get-Date -Date $webdata_time -Format s), was $(Get-Date -Date $offline_time -Format s)"
                $WebContent.Content | Out-File $writable_idxfile -Encoding utf8 -ErrorAction Stop
            }
        }

    }
}