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
        Specifies the target database where SqlWatch objects will be created and performance data will be stored. Defaults to SQLWATCH.
        Use this when you want to install SqlWatch into an existing database alongside other monitoring tools or when following specific naming conventions.

    .PARAMETER LocalFile
        Specifies the path to a local SqlWatch zip file to install instead of downloading from GitHub. Must be the official zip file distributed by SqlWatch maintainers.
        Use this when you have offline environments, want to control the specific version being deployed, or need to install from a pre-approved software repository.

    .PARAMETER Force
        Forces re-download of SqlWatch from GitHub even if a cached copy already exists locally in the dbatools data directory.
        Use this when you need to ensure you have the absolute latest version or when troubleshooting installation issues with potentially corrupted cached files.

    .PARAMETER PreRelease
        Downloads and installs the latest pre-release (beta) version of SqlWatch instead of the stable release branch.
        Use this when you need to test new features or bug fixes that haven't been released yet, but avoid in production environments.

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

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance where SqlWatch is installed or updated.

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name in computer\instance format
        - Database: The target database where SqlWatch was installed or updated
        - Status: The deployment status extracted from DACPAC publication results
        - DashboardPath: The full local file system path to the SqlWatch Dashboard directory for web UI access

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