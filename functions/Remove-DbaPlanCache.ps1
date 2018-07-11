function Remove-DbaPlanCache {
    <#
        .SYNOPSIS
            Removes adhoc and prepared plan caches is single use plans are over defined threshold.

        .DESCRIPTION
            Checks ahoc and prepared plan cache for each database, if over 100 MBs removes from the cache.

            This command automates that process.

            References: https://www.sqlskills.com/blogs/kimberly/plan-cache-adhoc-workloads-and-clearing-the-single-use-plan-cache-bloat/

            Note: This command removes the plans from all SQL instances on the destionation server but the process column is specific to -SqlInstance passed.

        .PARAMETER SqlInstance
            The target SQL Server instance.

        .PARAMETER SqlCredential
           Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Threshold
            Memory used threshold.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Memory
            Author: Tracy Boggiano, databasesuperhero.com

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Remove-DbaPlanCache

        .EXAMPLE
            Remove-DbaPlanCache -SqlInstance sql2017 -Threshold 200

            Logs into the SQL Server instance "sql2017" and removes plan caches if over 200 MBs.

        .EXAMPLE
            Remove-DbaPlanCache -SqlInstance sql2017 -SqlCredential (Get-Credential sqladmin)

            Logs into the SQL instance using the SQL Login 'sqladmin' and then Windows instance as 'ad\sqldba'
            and removes if Threshold over 100 MBs.
    #>
        [CmdletBinding(SupportsShouldProcess = $true)]
        Param (
            [parameter(Mandatory, ValueFromPipeline)]
            [Alias("ServerInstance", "SqlServer", "SqlServers")]
            [DbaInstanceParameter[]]$SqlInstance,
            [PSCredential]$SqlCredential,
            [int]$Threshold = 100,
            [switch]$EnableException
        )
        process {
            foreach ($instance in $SqlInstance) {
                try {
                    Write-Message -Level Verbose -Message "Connecting to $instance"
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $sqlcredential
                }
                catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                $results = Get-DbaQueryPlan -SqlInstance $instance -SqlCredential $SqlCredential -Threshold $Threshold

                if ($results.MB -ge $Threshold) {
                    if ($Pscmdlet.ShouldProcess("$server", "Cleared SQL Plans plan cache")) {
                        $server.Query("DBCC FREESYSTEMCACHE('SQL Plans')")
                    }
                    else {
                        Write-Message -Level Verbose -Message "Threshold [$Threshold] below $server plan cache size of [$($results.MB)]"
                    }
                }
            }
        }
    }