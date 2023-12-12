function Update-DbaBuildReference {
    <#
    .SYNOPSIS
        Updates the local reference looking online for the most up to date.

    .DESCRIPTION
        This function updates the local json files containing all the infos about SQL builds.
        It uses the setting 'assets.sqlbuildreference' to fetch it.
        To see your current setting, use Get-DbatoolsConfigValue -Name 'assets.sqlbuildreference'

    .PARAMETER LocalFile
        Specifies the path to a local file to install from instead of downloading from Github.

    .PARAMETER Proxy
        Specifies the URI for the proxy to be used. By default, a connection without a proxy is made. If it fails, a retry using default proxy
        settings is made.

    .PARAMETER ProxyCredential
        Specifies Credential for the proxy, when parameter "Proxy" is supplied. Only required if the proxy needs authentication.

    .PARAMETER ProxyUseDefaultCredentials
        Uses the credentials of the current user to access the proxy server. Requires Proxy parameter to be supplied.
        ProxyCredential and ProxyUseDefaultCredentials can't be used at the same time.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Utility, SqlBuild
        Author: Simone Bizzotto (@niphlod) | Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Update-DbaBuildReference

    .EXAMPLE
        PS C:\> Update-DbaBuildReference

        Looks online if there is a newer version of the build reference

    .EXAMPLE
        PS C:\> Update-DbaBuildReference -Proxy $ProxyURI -ProxyCredential $ProxyCred

        Looks online if there is a newer version of the build reference using the proxy supplied.

    .EXAMPLE
        PS C:\> Update-DbaBuildReference -LocalFile \\fileserver\Software\dbatools\dbatools-buildref-index.json

        Uses the given file instead of downloading the file to update the build reference

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(DefaultParameterSetName = 'Build')]
    param (
        [string]$LocalFile,
        [switch]$EnableException,
        [Parameter(ParameterSetName = 'Build')]
        [Parameter(Mandatory, ParameterSetName = 'Proxy')]
        [Parameter(ParameterSetName = 'ProxyDefaultCredential')]
        [URI]$Proxy,
        [Parameter(ParameterSetName = 'Proxy')]
        [pscredential]$ProxyCredential,
        [Parameter(ParameterSetName = 'ProxyDefaultCredential')]
        [switch]$ProxyUseDefaultCredentials
    )

    begin {
        function Get-DbaBuildReferenceIndexOnline {
            [CmdletBinding()]
            param (
                [bool]
                $EnableException,
                [URI]
                $Proxy,
                [pscredential]
                $ProxyCredential,
                [switch]
                $ProxyUseDefaultCredentials
            )
            $url = Get-DbatoolsConfigValue -Name 'assets.sqlbuildreference'
            $webRequestParams = @{
                Uri = $url
                UseBasicParsing = $true
            }
            if ($Proxy) {
                $webRequestParams['Proxy'] = $Proxy
            }
            if ($ProxyCredential) {
                $webRequestParams['ProxyCredential'] = $ProxyCredential
            }
            if ($ProxyUseDefaultCredentials) {
                $webRequestParams['ProxyUseDefaultCredentials'] = $ProxyUseDefaultCredentials
            }
            try {
                $webContent = Invoke-TlsWebRequest @webRequestParams -ErrorAction Stop
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
            $newContent = Get-DbaBuildReferenceIndexOnline -Proxy:$Proxy -ProxyCredential:$ProxyCredential -ProxyUseDefaultCredentials:$ProxyUseDefaultCredentials -EnableException $EnableException
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