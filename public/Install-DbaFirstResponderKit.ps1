function Install-DbaFirstResponderKit {
    <#
    .SYNOPSIS
        Downloads and installs Brent Ozar's First Responder Kit diagnostic stored procedures.

    .DESCRIPTION
        Downloads and installs the First Responder Kit (FRK), a collection of stored procedures designed for SQL Server health checks, performance analysis, and troubleshooting. The FRK includes essential procedures like sp_Blitz for overall health assessment, sp_BlitzCache for query performance analysis, sp_BlitzIndex for index recommendations, and sp_BlitzFirst for real-time performance monitoring.

        This function automatically downloads the latest version from GitHub, caches it locally, and installs the procedures into your specified database. You can install the complete toolkit or select specific procedures based on your needs. The function handles version compatibility automatically, skipping procedures that aren't supported on older SQL Server versions.

        Perfect for DBAs who need standardized diagnostic tools across multiple SQL Server instances without manually downloading and deploying scripts.

        First Responder Kit links:
        http://FirstResponderKit.org
        https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database to install the First Responder Kit stored procedures into

    .PARAMETER Branch
        Specifies an alternate branch of the First Responder Kit to install.
        Allowed values:
            main (default)
            dev

    .PARAMETER LocalFile
        Specifies the path to a local file to install FRK from. This *should* be the zip file as distributed by the maintainers.
        If this parameter is not specified, the latest version will be downloaded and installed from https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit

    .PARAMETER OnlyScript
        Specifies the name(s) of the script(s) to run for installation. Wildcards are permitted.
        This way only part of the First Responder Kit can be installed.
        Using one of the three official Install-* scripts (Install-All-Scripts.sql, Install-Core-Blitz-No-Query-Store.sql, Install-Core-Blitz-With-Query-Store.sql) is possible this way.
        Even removing the First Responder Kit is possible by using the official Uninstall.sql.

    .PARAMETER Force
        If this switch is enabled, the FRK will be downloaded from the internet even if previously cached.

    .PARAMETER Confirm
        Prompts to confirm actions

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, FirstResponderKit
        Author: Tara Kizer, Brent Ozar Unlimited (brentozar.com)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://www.brentozar.com/responder

    .LINK
        https://dbatools.io/Install-DbaFirstResponderKit

    .EXAMPLE
        PS C:\> Install-DbaFirstResponderKit -SqlInstance server1 -Database master

        Logs into server1 with Windows authentication and then installs the FRK in the master database.

    .EXAMPLE
        PS C:\> Install-DbaFirstResponderKit -SqlInstance server1\instance1 -Database DBA

        Logs into server1\instance1 with Windows authentication and then installs the FRK in the DBA database.

    .EXAMPLE
        PS C:\> Install-DbaFirstResponderKit -SqlInstance server1\instance1 -Database master -SqlCredential $cred

        Logs into server1\instance1 with SQL authentication and then installs the FRK in the master database.

    .EXAMPLE
        PS C:\> Install-DbaFirstResponderKit -SqlInstance sql2016\standardrtm, sql2016\sqlexpress, sql2014

        Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs the FRK in the master database.

    .EXAMPLE
        PS C:\> $servers = "sql2016\standardrtm", "sql2016\sqlexpress", "sql2014"
        PS C:\> $servers | Install-DbaFirstResponderKit

        Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs the FRK in the master database.

    .EXAMPLE
        PS C:\> Install-DbaFirstResponderKit -SqlInstance sql2016 -Branch dev

        Installs the dev branch version of the FRK in the master database on sql2016 instance.

    .EXAMPLE
        PS C:\> Install-DbaFirstResponderKit -SqlInstance sql2016 -OnlyScript sp_Blitz.sql, sp_BlitzWho.sql, SqlServerVersions.sql

        Installs only the procedures sp_Blitz and sp_BlitzWho and the table SqlServerVersions by running the corresponding scripts.

    .EXAMPLE
        PS C:\> Install-DbaFirstResponderKit -SqlInstance sql2016 -OnlyScript Install-All-Scripts.sql

        Installs the First Responder Kit using the official install script.

    .EXAMPLE
        PS C:\> Install-DbaFirstResponderKit -SqlInstance sql-server-001.database.windows.net -OnlyScript Install-Azure.sql

        Installs the First Responder Kit using the official install script for Azure SQL Database.

    .EXAMPLE
        PS C:\> Install-DbaFirstResponderKit -SqlInstance sql2016 -OnlyScript Uninstall.sql

        Uninstalls the First Responder Kit by running the official uninstall script.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet('main', 'dev')]
        [string]$Branch = "main",
        [object]$Database = "master",
        [string]$LocalFile,
        [ValidateSet('Install-All-Scripts.sql', 'Install-Azure.sql',
            'sp_Blitz.sql', 'sp_BlitzFirst.sql', 'sp_BlitzIndex.sql', 'sp_BlitzCache.sql', 'sp_BlitzWho.sql',
            'sp_BlitzAnalysis.sql', 'sp_BlitzBackups.sql', 'sp_BlitzLock.sql',
            'sp_DatabaseRestore.sql', 'sp_ineachdb.sql',
            'SqlServerVersions.sql', 'Uninstall.sql')]
        [string[]]$OnlyScript,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        # Do we need a new local cached version of the software?
        $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
        $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child "SQL-Server-First-Responder-Kit-$Branch"
        if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
            if ($PSCmdlet.ShouldProcess('FirstResponderKit', 'Update local cached copy of the software')) {
                try {
                    Save-DbaCommunitySoftware -Software FirstResponderKit -Branch $Branch -LocalFile $LocalFile -EnableException
                } catch {
                    Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_
                }
            }
        }

        if ($OnlyScript) {
            $sqlScripts = @()
            foreach ($script in $OnlyScript) {
                $sqlScript = Get-ChildItem $LocalCachedCopy -Filter $script
                if ($sqlScript) {
                    $sqlScripts += $sqlScript
                } else {
                    Write-Message -Level Warning -Message "Script $script not found in $LocalCachedCopy, skipping."
                }
            }
        } else {
            $sqlScripts = Get-ChildItem $LocalCachedCopy -Filter "sp_*.sql"
            $sqlScripts += Get-ChildItem $LocalCachedCopy -Filter "SqlServerVersions.sql"
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            if ($PSCmdlet.ShouldProcess($instance, "Connecting to $instance")) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -NonPooledConnection
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
            }
            if ($PSCmdlet.ShouldProcess($database, "Installing FRK procedures in $database on $instance")) {
                Write-Message -Level Verbose -Message "Starting installing/updating the First Responder Kit stored procedures in $database on $instance."
                $allprocedures_query = "SELECT name FROM sys.procedures WHERE is_ms_shipped = 0"
                $allprocedures = ($server.Query($allprocedures_query, $Database)).Name

                # Install/Update each FRK stored procedure
                foreach ($script in $sqlScripts) {
                    $scriptName = $script.Name
                    $scriptError = $false

                    $baseres = [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $Database
                        Name         = $script.BaseName
                        Status       = $null
                    }

                    if ($scriptName -eq "sp_BlitzQueryStore.sql" -and ($server.VersionMajor -lt 13)) {
                        Write-Message -Level Warning -Message "$instance found to be below SQL Server 2016, skipping $scriptName"
                        $baseres.Status = 'Skipped'
                        $baseres
                        continue
                    }
                    if ($scriptName -eq "sp_BlitzInMemoryOLTP.sql" -and ($server.VersionMajor -lt 12)) {
                        Write-Message -Level Warning -Message "$instance found to be below SQL Server 2014, skipping $scriptName"
                        $baseres.Status = 'Skipped'
                        $baseres
                        continue
                    }
                    if ($Pscmdlet.ShouldProcess($instance, "installing/updating $scriptName in $database")) {
                        try {
                            Invoke-DbaQuery -SqlInstance $server -Database $Database -File $script.FullName -EnableException -Verbose:$false
                        } catch {
                            Write-Message -Level Warning -Message "Could not execute at least one portion of $scriptName in $Database on $instance." -ErrorRecord $_
                            $scriptError = $true
                        }

                        if ($scriptError) {
                            $baseres.Status = 'Error'
                        } elseif ($script.BaseName -in $allprocedures) {
                            $baseres.Status = 'Updated'
                        } else {
                            $baseres.Status = 'Installed'
                        }
                        $baseres
                    }
                }
            }
            Write-Message -Level Verbose -Message "Finished installing/updating the First Responder Kit stored procedures in $database on $instance."
        }
    }
}