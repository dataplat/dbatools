Function Uninstall-DbaSqlWatch {
    <#
    .SYNOPSIS
        Uninstalls SqlWatch.

    .DESCRIPTION
        Deletes all user objects, agent jobs, and historical data associated with SqlWatch.

    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database to install SqlWatch into. Defaults to master.

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
        https://dbatools.io/Uninstall-DbaSqlWatch

    .EXAMPLE
        Uninstall-DbaSqlWatch -SqlInstance server1

        Deletes all user objects, agent jobs, and historical data associated with SqlWatch from the master database.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database = "master",
        [switch]$EnableException
    )

    begin {

        # validate database parameter

        if (Test-Bound -Not -ParameterName 'DacfxPath') {
            $dacfxPath = "$script:PSModuleRoot\bin\smo\Microsoft.SqlServer.Dac.dll"
        }

        if ((Test-Path $dacfxPath) -eq $false) {
            Stop-Function -Message 'No usable version of Dac Fx found.'
        } else {
            try {
                Add-Type -Path $dacfxPath
                Write-Message -Level Verbose -Message "Dac Fx loaded."
            } catch {
                Stop-Function -Message 'No usable version of Dac Fx found.' -ErrorRecord $_
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # get SqlWatch objects
            $tables = Get-DbaDbTable -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "sql_perf_mon_*" -or $PSItem.Name -like "logger_*" }
            $views = Get-DbaDbView -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "vw_sql_perf_mon_*" }
            $sprocs = Get-DbaDbStoredProcedure -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "sp_sql_perf_mon_*" -or $PSItem.Name -like "usp_logger_*" }
            $agentJobs = Get-DbaAgentJob -SqlInstance $server | Where-Object { ($PSItem.Name -like "SqlWatch-*") -or ($PSItem.Name -like "DBA-PERF-*") }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch SQL Agent jobs")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SQL Agent jobs from $server."
                    $agentJobs | Remove-DbaAgentJob | Out-Null
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch Agent Jobs on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch stored procedures")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch stored procedures from $database on $server."
                    $dropScript = ""
                    $sprocs | ForEach-Object {
                        $dropScript += "DROP PROCEDURE $($PSItem.Name);`n"
                    }
                    if ($dropScript) {
                        Invoke-DbaQuery -SqlInstance $server -Database $Database -Query $dropScript
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch stored procedures from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch views")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch views from $database on $server."
                    $dropScript = ""
                    $views | ForEach-Object {
                        $dropScript += "DROP VIEW $($PSItem.Name);`n"
                    }
                    if ($dropScript) {
                        Invoke-DbaQuery -SqlInstance $server -Database $Database -Query $dropScript
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch views from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch tables")) {
                try {
                    Write-Message -Level Verbose -Message "Removing foreign keys from SqlWatch tables in $database on $server."
                    if ($tables.ForeignKeys) {
                        $tables.ForeignKeys | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all foreign keys from SqlWatch tables in $database on $server." -ErrorRecord $_ -Target $server -Continue
                }

                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch tables from $database on $server."
                    $dropScript = ""
                    $tables | ForEach-Object {
                        $dropScript += "DROP TABLE $($PSItem.Name);`n"
                    }
                    if ($dropScript) {
                        Invoke-DbaQuery -SqlInstance $server -Database $Database -Query $dropScript
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch tables from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Unpublishing DACPAC")) {
                try {
                    Write-Message -Level Verbose -Message "Unpublishing SqlWatch DACPAC from $database on $server."
                    $connectionString = $server | Select-Object -ExpandProperty ConnectionContext
                    $dacServices = New-Object Microsoft.SqlServer.Dac.DacServices $connectionString
                    $dacServices.Unregister($Database)
                } catch {
                    Stop-Function -Message "Failed to unpublish SqlWatch DACPAC from $database on $server." -ErrorRecord $_
                }
            }
        }
    }
}