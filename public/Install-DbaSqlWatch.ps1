function Install-DbaSqlWatch {
    <#
    .SYNOPSIS
        Installs or updates SqlWatch monitoring solution on SQL Server instances.

    .DESCRIPTION
        Deploys SqlWatch, an open-source SQL Server monitoring and performance collection tool, to one or more SQL Server instances. SqlWatch continuously gathers performance metrics, wait statistics, and system information into dedicated tables for historical analysis and alerting.

        This function automatically downloads the latest SqlWatch release from GitHub (or uses a local file), then deploys it to the specified database using DACPAC technology. SqlWatch creates its own database objects to collect and store performance data, making it useful for DBAs who need ongoing monitoring without third-party agents or expensive monitoring solutions.

        The installed SqlWatch system runs autonomously via SQL Agent jobs, collecting data at regular intervals. It includes a web dashboard for viewing metrics and can be customized for specific monitoring requirements.

        More information: https://sqlwatch.io/

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

        # Do we need a new local cached version of the software?
        $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
        if ($PreRelease) {
            $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child "SQLWATCH-prerelease"
            $branch = 'prerelease'
        } else {
            $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child "SQLWATCH"
            $branch = 'release'
        }
        if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
            if ($PSCmdlet.ShouldProcess('SQLWATCH', 'Update local cached copy of the software')) {
                try {
                    Save-DbaCommunitySoftware -Software SQLWATCH -Branch $branch -LocalFile $LocalFile -EnableException
                } catch {
                    Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_
                }
            }
        }

        $stepCounter = 0

        if ($Database -eq 'tempdb') {
            Stop-Function -Message "Installation to tempdb not supported"
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if ($PSEdition -eq 'Core') {
            Stop-Function -Message "PowerShell Core is not supported, please use Windows PowerShell."
            return
        }
        $totalSteps = $stepCounter + $SqlInstance.Count * 2
        foreach ($instance in $SqlInstance) {
            if ($PSCmdlet.ShouldProcess($instance, "Installing SqlWatch on $Database")) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Starting installing/updating SqlWatch in $database on $instance" -TotalSteps $totalSteps


                try {
                    # create a publish profile and publish DACPAC
                    $DacPacPath = Get-ChildItem -Filter "SqlWatch.dacpac" -Path $localCachedCopy -Recurse | Select-Object -ExpandProperty FullName
                    $PublishOptions = @{
                        RegisterDataTierApplication = $true
                    }

                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Publishing SqlWatch dacpac to $database on $instance" -TotalSteps $totalSteps
                    $DacProfile = New-DbaDacProfile -SqlInstance $server -Database $Database -Path $localCachedCopy -PublishOptions $PublishOptions | Select-Object -ExpandProperty FileName
                    $PublishResults = Publish-DbaDacPackage -SqlInstance $server -Database $Database -Path $DacPacPath -PublishXml $DacProfile
                    Remove-Item -Path $DacProfile

                    # parse results
                    $parens = Select-String -InputObject $PublishResults.Result -Pattern "\(([^\)]+)\)" -AllMatches
                    if ($parens.matches) {
                        $ExtractedResult = $parens.matches | Select-Object -Last 1
                    }

                    [PSCustomObject]@{
                        ComputerName  = $PublishResults.ComputerName
                        InstanceName  = $PublishResults.InstanceName
                        SqlInstance   = $PublishResults.SqlInstance
                        Database      = $PublishResults.Database
                        Status        = $ExtractedResult
                        DashboardPath = $localCachedCopy + '\SqlWatch.Dashboard'
                    }
                } catch {
                    Stop-Function -Message "DACPAC failed to publish to $database on $instance." -ErrorRecord $_ -Target $instance -Continue
                }

                Write-Message -Level Verbose -Message "Finished installing/updating SqlWatch in $database on $instance."
            }
        }
    }
}