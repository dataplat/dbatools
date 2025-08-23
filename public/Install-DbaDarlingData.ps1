function Install-DbaDarlingData {
    <#
    .SYNOPSIS
        Downloads and installs Erik Darling's performance monitoring stored procedures

    .DESCRIPTION
        Downloads, extracts and installs Erik Darling's collection of performance monitoring stored procedures from the DarlingData GitHub repository. This gives you access to popular diagnostic tools like sp_HumanEvents for extended events analysis, sp_PressureDetector for memory pressure monitoring, sp_QuickieStore for Query Store analysis, and several others that help with SQL Server performance troubleshooting. The function handles version compatibility automatically (for example, skipping sp_QuickieStore on SQL Server versions below 2016) and only installs the stored procedures themselves, not other repository contents like views or documentation.

        DarlingData links:
        https://www.erikdarling.com
        https://github.com/erikdarlingdata/DarlingData

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the target database where Erik Darling's performance monitoring stored procedures will be installed.
        Commonly set to master, DBA, or a dedicated administrative database where diagnostic procedures are centralized.
        The database must already exist on the target instance.

    .PARAMETER Branch
        Specifies which branch of the DarlingData repository to install from.
        Use 'main' for the latest stable release or 'dev' for experimental features and bug fixes.
        The dev branch may contain newer procedures or fixes not yet available in the main branch.
        Allowed values:
            main (default)
            dev

    .PARAMETER Procedure
        Specifies which specific performance monitoring procedures to install instead of the complete collection.
        Use this when you only need particular diagnostic tools or want to avoid installing procedures you don't use.
        Each procedure addresses different performance areas: HumanEvents for extended events analysis, PressureDetector for memory pressure monitoring, QuickieStore for Query Store analysis.
        Allowed Values or Combination of Values:
            All (default, to install all procedures)
            HumanEvents (to install sp_HumanEvents)
            PressureDetector (to install sp_PressureDetector)
            QuickieStore (to install sp_QuickieStore)
            HumanEventsBlockViewer (to install sp_HumanEventsBlockViewer)
            LogHunter (to install sp_LogHunter)
            HealthParser (to install sp_HealthParser)
            IndexCleanup (to install sp_IndexCleanup)
            PerfCheck (to install sp_PerfCheck)
        The following shorthands are allowed, ordered as above: Human, Pressure, Quickie, Block, Log, Health, Index, Perf.

    .PARAMETER LocalFile
        Specifies the path to a local zip file containing the DarlingData procedures instead of downloading from GitHub.
        Use this when internet access is restricted, when you need to install a specific version, or when you have a pre-downloaded copy.
        The file must be the official zip distribution from the DarlingData repository maintainers.
        If this parameter is not specified, the latest version will be downloaded and installed from https://github.com/erikdarlingdata/DarlingData

    .PARAMETER Force
        Forces a fresh download of the DarlingData procedures even if a cached version already exists locally.
        Use this when you need to ensure you have the absolute latest version or when troubleshooting installation issues.
        Without this switch, the function uses the cached version if available to improve performance.

    .PARAMETER Confirm
        Prompts to confirm actions

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, Erik Darling, DarlingData
        Author: Ant Green (@ant_green)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Install-DbaDarlingData

    .EXAMPLE
        PS C:\> Install-DbaDarlingData -SqlInstance server1 -Database master

        Logs into server1 with Windows authentication and then installs all of Erik's scripts in the master database.

    .EXAMPLE
        PS C:\> Install-DbaDarlingData -SqlInstance server1\instance1 -Database DBA

        Logs into server1\instance1 with Windows authentication and then installs all of Erik's scripts in the DBA database.

    .EXAMPLE
        PS C:\> Install-DbaDarlingData -SqlInstance server1\instance1 -Database master -SqlCredential $cred

        Logs into server1\instance1 with SQL authentication and then installs all of Erik's scripts in the master database.

    .EXAMPLE
        PS C:\> Install-DbaDarlingData -SqlInstance sql2016\standardrtm, sql2016\sqlexpress, sql2014

        Logs into sql2016\standardrtm, sql2016\sqlexpress and sql2014 with Windows authentication and then installs al of Erik's scripts in the master database.

    .EXAMPLE
        PS C:\> Install-DbaDarlingData -SqlInstance sql2016 -Branch dev

        Installs the dev branch version of Erik's scripts in the master database on sql2016 instance.

    .EXAMPLE
        PS C:\> Install-DbaDarlingData -SqlInstance server1\instance1 -Database DBA -Procedure Human, Pressure

        Logs into server1\instance1 with Windows authentication and then installs sp_HumanEvents and sp_PressureDetector of Erik's scripts in the DBA database.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object]$Database = "master",
        [ValidateSet('main', 'dev')]
        [string]$Branch = "main",
        [ValidateSet('All', 'Human', 'HumanEvents', 'Pressure', 'PressureDetector', 'Quickie', 'QuickieStore', 'Block', 'HumanEventsBlockViewer', 'Log', 'LogHunter', 'Health', 'HealthParser', 'Index', 'IndexCleanup', 'Perf', 'PerfCheck')]
        [string[]]$Procedure = "All",
        [string]$LocalFile,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        # Do we need a new local cached version of the software?
        $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
        $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child "DarlingData-$Branch"
        if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
            if ($PSCmdlet.ShouldProcess('DarlingData', 'Update local cached copy of the software')) {
                try {
                    Save-DbaCommunitySoftware -Software DarlingData -Branch $Branch -LocalFile $LocalFile -EnableException
                } catch {
                    Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_
                }
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            if ($PSCmdlet.ShouldProcess($instance, "Connecting to $instance")) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
            }

            $db = $server.Databases[$Database]
            if ($null -eq $db) {
                Stop-Function -Message "Database $Database not found on $instance. Skipping." -Target $instance -Continue
            }

            if ($PSCmdlet.ShouldProcess($database, "Installing DarlingData procedures in $database on $instance")) {
                Write-Message -Level Verbose -Message "Starting installing/updating the DarlingData stored procedures in $database on $instance."
                $allprocedures_query = "SELECT name FROM sys.procedures WHERE is_ms_shipped = 0"
                $allprocedures = ($server.Query($allprocedures_query, $Database)).Name

                if ($Procedure -contains "All") {
                    # We install all scripts
                    $sqlScripts = Get-ChildItem $localCachedCopy -Filter "DarlingData.sql" -Recurse
                } else {
                    # We only install specific scripts that as located in different subdirectories and exclude the example
                    $sqlScripts = @( )
                    if ($Procedure -contains "Human" -or $Procedure -contains "HumanEvents") {
                        $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_HumanEvents.sql" -Recurse
                    }
                    if ($Procedure -contains "Pressure" -or $Procedure -contains "PressureDetector") {
                        $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_PressureDetector.sql" -Recurse
                    }
                    if ($Procedure -contains "Quickie" -or $Procedure -contains "QuickieStore") {
                        $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_QuickieStore.sql" -Recurse
                    }
                    if ($Procedure -contains "Block" -or $Procedure -contains "HumanEventsBlockViewer") {
                        $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_HumanEventsBlockViewer.sql" -Recurse
                    }
                    if ($Procedure -contains "Log" -or $Procedure -contains "LogHunter") {
                        $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_LogHunter.sql" -Recurse
                    }
                    if ($Procedure -contains "Health" -or $Procedure -contains "HealthParser") {
                        $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_HealthParser.sql" -Recurse
                    }
                    if ($Procedure -contains "Index" -or $Procedure -contains "IndexCleanup") {
                        $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_IndexCleanup.sql" -Recurse
                    }
                    if ($Procedure -contains "Perf" -or $Procedure -contains "PerfCheck") {
                        $sqlScripts += Get-ChildItem $localCachedCopy -Filter "sp_PerfCheck.sql" -Recurse
                    }
                }

                foreach ($script in $sqlScripts) {
                    $sql = Get-Content $script.FullName -Raw
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

                    if ($scriptName -eq "sp_QuickieStore.sql" -and ($server.VersionMajor -lt 13)) {
                        Write-Message -Level Warning -Message "$instance found to be below SQL Server 2016, skipping $scriptName"
                        $baseres.Status = 'Skipped'
                        $baseres
                        continue
                    }
                    if ($Pscmdlet.ShouldProcess($instance, "installing/updating $scriptName in $database")) {
                        try {
                            foreach ($query in ($sql -Split "\nGO\b")) {
                                $null = $db.Query($query)
                            }
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
            Write-Message -Level Verbose -Message "Finished installing/updating the DarlingData stored procedures in $database on $instance."
        }
    }
}