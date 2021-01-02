function Install-DbaSqlWatch {
    <#
    .SYNOPSIS
        Installs or updates SqlWatch.

    .DESCRIPTION
        Downloads, extracts and installs or updates SqlWatch.
        https://sqlwatch.io/

    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database to install SqlWatch into. Defaults to SQLWATCH.

    .PARAMETER LocalFile
        Specifies the path to a local file to install SqlWatch from. This *should* be the zipfile as distributed by the maintainers.
        If this parameter is not specified, the latest version will be downloaded and installed from https://github.com/marcingminski/sqlwatch

    .PARAMETER Force
        If this switch is enabled, SqlWatch will be downloaded from the internet even if previously cached.

    .PARAMETER PreRelease
        If specified, a pre-release (beta) will be downloaded rather than a stable release

    .PARAMETER Confirm
        Prompts to confirm actions

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, SqlWatch
        Author: Ken K (github.com/koglerk)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://sqlwatch.io

    .LINK
        https://dbatools.io/Install-DbaSqlWatch

    .EXAMPLE
        Install-DbaSqlWatch -SqlInstance server1

        Logs into server1 with Windows authentication and then installs SqlWatch in the SQLWATCH database.

    .EXAMPLE
        Install-DbaSqlWatch -SqlInstance server1\instance1 -Database DBA

        Logs into server1\instance1 with Windows authentication and then installs SqlWatch in the DBA database.

    .EXAMPLE
        Install-DbaSqlWatch -SqlInstance server1\instance1 -Database DBA -SqlCredential $cred

        Logs into server1\instance1 with SQL authentication and then installs SqlWatch in the DBA database.

    .EXAMPLE
        Install-DbaSqlWatch -SqlInstance sql2016\standardrtm, sql2016\sqlexpress, sql2014

        Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs SqlWatch in the SQLWATCH database.

    .EXAMPLE
        $servers = "sql2016\standardrtm", "sql2016\sqlexpress", "sql2014"
        $servers | Install-DbaSqlWatch

        Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs SqlWatch in the SQLWATCH database.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database = "SQLWATCH",
        [string]$LocalFile,
        [switch]$PreRelease,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $stepCounter = 0

        $DbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"
        $tempFolder = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
        $zipfile = "$tempFolder\SqlWatch.zip"

        $releasetxt = $(if ($PreRelease) { "pre-release" } else { "release" })

        if (-not $LocalFile) {
            if ($PSCmdlet.ShouldProcess($env:computername, "Downloading latest $releasetxt from GitHub")) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Downloading latest release from GitHub"
                # query the releases to find the latest, check and see if its cached
                $ReleasesUrl = "https://api.github.com/repos/marcingminski/sqlwatch/releases"
                $DownloadBase = "https://github.com/marcingminski/sqlwatch/releases/download/"

                Write-Message -Level Verbose -Message "Checking GitHub for the latest $releasetxt."
                $LatestReleaseUrl = ((Invoke-TlsWebRequest -UseBasicParsing -Uri $ReleasesUrl | ConvertFrom-Json) | Where-Object { $_.prerelease -eq $PreRelease })[0].assets[0].browser_download_url

                Write-Message -Level VeryVerbose -Message "Latest $releasetxt is available at $LatestReleaseUrl"
                $LocallyCachedZip = Join-Path -Path $DbatoolsData -ChildPath $($LatestReleaseUrl -replace $DownloadBase, '');

                # if local cached copy exists, use it, otherwise download a new one
                if (-not $Force) {

                    # download from github
                    Write-Message -Level Verbose "Downloading $LatestReleaseUrl"
                    try {
                        Invoke-TlsWebRequest $LatestReleaseUrl -OutFile $zipfile -ErrorAction Stop -UseBasicParsing
                    } catch {
                        #try with default proxy and usersettings
                        (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                        Invoke-TlsWebRequest $LatestReleaseUrl -OutFile $zipfile -ErrorAction Stop -UseBasicParsing
                    }

                    # copy the file from temp to local cache
                    Write-Message -Level Verbose "Copying $zipfile to $LocallyCachedZip"
                    try {
                        New-Item -Path $LocallyCachedZip -ItemType File -Force | Out-Null
                        Copy-Item -Path $zipfile -Destination $LocallyCachedZip -Force
                    } catch {
                        # should we stop the function if the file copy fails?
                        # here to avoid an empty catch
                        $null = 1
                    }
                }
            }
        } else {

            # $LocalFile was passed, so use it
            if ($PSCmdlet.ShouldProcess($env:computername, "Copying local file to temp directory")) {

                if ($LocalFile.EndsWith("zip")) {
                    $LocallyCachedZip = $zipfile
                    Copy-Item -Path $LocalFile -Destination $LocallyCachedZip -Force
                } else {
                    $LocallyCachedZip = (Join-Path -path $tempFolder -childpath "SqlWatch.zip")
                    Copy-Item -Path $LocalFile -Destination $LocallyCachedZip -Force
                }
            }
        }

        # expand the zip file
        if ($PSCmdlet.ShouldProcess($env:computername, "Unpacking zipfile")) {
            Write-Message -Level VeryVerbose "Unblocking $LocallyCachedZip"
            Unblock-File $LocallyCachedZip -ErrorAction SilentlyContinue
            $LocalCacheFolder = Split-Path $LocallyCachedZip -Parent

            Write-Message -Level Verbose "Extracting $LocallyCachedZip to $LocalCacheFolder"
            try {
                Expand-Archive -Path $LocallyCachedZip -DestinationPath $LocalCacheFolder -Force
            } catch {
                Stop-Function -Message "Unable to extract $LocallyCachedZip. Archive may not be valid." -ErrorRecord $_
                return
            }

            Write-Message -Level VeryVerbose "Deleting $LocallyCachedZip"
            Remove-Item -Path $LocallyCachedZip
        }
        if ($Database -eq 'tempdb') {
            Stop-Function -Message "Installation to tempdb not supported"
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        $totalSteps = $stepCounter + $SqlInstance.Count * 2
        foreach ($instance in $SqlInstance) {
            if ($PSCmdlet.ShouldProcess($instance, "Installing SqlWatch on $Database")) {
                try {
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure." -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Starting installing/updating SqlWatch in $database on $instance" -TotalSteps $totalSteps


                try {
                    # create a publish profile and publish DACPAC
                    $DacPacPath = Get-ChildItem -Filter "SqlWatch.dacpac" -Path $LocalCacheFolder -Recurse | Select-Object -ExpandProperty FullName
                    $PublishOptions = @{
                        RegisterDataTierApplication = $true
                    }

                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Publishing SqlWatch dacpac to $database on $instance" -TotalSteps $totalSteps
                    $DacProfile = New-DbaDacProfile -SqlInstance $server -Database $Database -Path $LocalCacheFolder -PublishOptions $PublishOptions | Select-Object -ExpandProperty FileName
                    $PublishResults = Publish-DbaDacPackage -SqlInstance $server -Database $Database -Path $DacPacPath -PublishXml $DacProfile

                    # parse results
                    $parens = Select-String -InputObject $PublishResults.Result -Pattern "\(([^\)]+)\)" -AllMatches
                    if ($parens.matches) {
                        $ExtractedResult = $parens.matches | Select-Object -Last 1
                    }

                    [PSCustomObject]@{
                        ComputerName = $PublishResults.ComputerName
                        InstanceName = $PublishResults.InstanceName
                        SqlInstance  = $PublishResults.SqlInstance
                        Database     = $PublishResults.Database
                        Status       = $ExtractedResult
                    }
                } catch {
                    Stop-Function -Message "DACPAC failed to publish to $database on $instance." -ErrorRecord $_ -Target $instance -Continue
                }

                Write-Message -Level Verbose -Message "Finished installing/updating SqlWatch in $database on $instance."
            }
        }
    }
}