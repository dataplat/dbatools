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
        Specifies the target database where the First Responder Kit stored procedures will be installed. Defaults to master.
        Consider using a dedicated DBA or utility database instead of master for better organization and maintenance.

    .PARAMETER Branch
        Specifies which GitHub branch of the First Responder Kit to download and install. Defaults to 'main' for the stable release.
        Use 'dev' to install the development branch when you need the latest features or bug fixes that haven't been released yet.

    .PARAMETER LocalFile
        Specifies the path to a local zip file containing the First Responder Kit scripts instead of downloading from GitHub.
        Use this when you have a specific version cached locally, when internet access is restricted, or when you need to install a customized version of the toolkit.

    .PARAMETER OnlyScript
        Specifies specific script files to install instead of the entire First Responder Kit. Accepts multiple script names and wildcards.
        Use this to install only the procedures you need (like sp_Blitz.sql, sp_BlitzCache.sql) or to run official install scripts (Install-All-Scripts.sql, Install-Azure.sql). Also supports Uninstall.sql to remove the toolkit.

    .PARAMETER Force
        Forces a fresh download of the First Responder Kit from GitHub even if a cached version already exists locally.
        Use this when you want to ensure you have the absolute latest version or when the cached version may be corrupted.

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

    .OUTPUTS
        PSCustomObject

        Returns one object per script file processed. By default, returns one object per .sql file matching the sp_*.sql pattern plus SqlServerVersions.sql. When using the -OnlyScript parameter, only specified scripts are processed and returned.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The target database where scripts are installed
        - Name: The base name of the script file (without extension)
        - Status: Installation status - 'Installed' (newly created), 'Updated' (already existed and was overwritten), 'Skipped' (version incompatible like sp_BlitzQueryStore on SQL Server < 2016 or sp_BlitzInMemoryOLTP on SQL Server < 2014), or 'Error' (script execution failed)

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