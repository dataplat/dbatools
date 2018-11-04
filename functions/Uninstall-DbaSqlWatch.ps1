#ValidationTags#CodeStyle,Messaging,FlowControl,Pipeline#
Function Uninstall-DbaSqlWatch {
    <#
        .SYNOPSIS
            Uninstalls SqlWatch.

        .DESCRIPTION
            Deletes all user objects, agent jobs, and historical data associated with SqlWatch.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            Specifies the database to install SqlWatch into.

        .PARAMETER Confirm
            Prompts to confirm actions

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: SqlWatch
            Author: marcingminski, koglerk
            Website: https://sqlwatch.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Uninstall-DbaSqlWatch

        .EXAMPLE
            Uninstall-DbaSqlWatch -SqlInstance server1 -Database master

            Deletes all user objects, agent jobs, and historical data associated with SqlWatch from the master database.

        .EXAMPLE
            Install-DbaSqlWatch -SqlInstance server1\instance1 -Database DBA

            Logs into server1\instance1 with Windows authentication and then deletes all user objects, agent jobs, and historical data associated with SqlWatch from the DBA database.

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [object]$Database = "master",
        [switch]$Force,
        [Alias('Silent')]
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

            # get SQWATCH objects
            $tables = Get-DbaDbTable -SqlInstance $instance -Database $Database | Where-Object {$PSItem.Name -like "sql_perf_mon_*" -or $PSItem.Name -like "logger_*" } 
            $views = Get-DbaDbView -SqlInstance $instance -Database $Database | Where-Object {$PSItem.Name -like "vw_sql_perf_mon_*" }
            $sprocs = Get-DbaDbStoredProcedure -SqlInstance $instance -Database $Database | Where-Object {$PSItem.Name -like "sp_sql_perf_mon_*" -or $PSItem.Name -like "usp_logger_*" }
            $agentJobs = Get-DbaAgentJob -SqlInstance $instance | Where-Object { ($PSItem.Name -like "SqlWatch-*") -or ($PSItem.Name -like "DBA-PERF-*") }
            
            if ($PSCmdlet.ShouldProcess($instance, "Removing SqlWatch SQL Agent jobs")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SQL Agent jobs from $instance."
                    $agentJobs | Remove-DbaAgentJob | Out-Null
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch Agent Jobs on $instance." -ErrorRecord $_ -Target $instance -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($instance, "Removing SqlWatch stored procedures")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch stored procedures from $database on $instance."
                    $dropScript = ""
                    $sprocs | ForEach-Object {
                        $dropScript += "DROP PROCEDURE $($PSItem.Name);`n"
                    }
                    if ($dropScript) { 
                        Invoke-DbaQuery -SqlInstance $instance -Database $Database -Query $dropScript 
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch stored procedures from $database on $instance." -ErrorRecord $_ -Target $instance -Continue
                }
            }
        
            if ($PSCmdlet.ShouldProcess($instance, "Removing SqlWatch views")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch views from $database on $instance."
                    $dropScript = ""
                    $views | ForEach-Object {
                        $dropScript += "DROP VIEW $($PSItem.Name);`n"
                    }
                    if ($dropScript) { 
                        Invoke-DbaQuery -SqlInstance $instance -Database $Database -Query $dropScript
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch views from $database on $instance." -ErrorRecord $_ -Target $instance -Continue
                }
            }
        
            if ($PSCmdlet.ShouldProcess($instance, "Removing SqlWatch tables")) {
                try {
                    Write-Message -Level Verbose -Message "Removing foreign keys from SqlWatch tables in $database on $instance."
                    if ($tables.ForeignKeys) {
                        $tables.ForeignKeys | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all foreign keys from SqlWatch tables in $database on $instance." -ErrorRecord $_ -Target $instance -Continue
                }        

                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch tables from $database on $instance."
                    $dropScript = ""
                    $tables | ForEach-Object {
                        $dropScript += "DROP TABLE $($PSItem.Name);`n"
                    }
                    if ($dropScript) { 
                        Invoke-DbaQuery -SqlInstance $instance -Database $Database -Query $dropScript
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch tables from $database on $instance." -ErrorRecord $_ -Target $instance -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($instance, "Unpublishing DACPAC")) {
                try {
                    Write-Message -Level Verbose -Message "Unpublishing SqlWatch DACPAC from $database on $instance."
                    $connectionString = Connect-DbaInstance $instance | Select-Object -ExpandProperty ConnectionContext
                    $dacServices = New-Object Microsoft.SqlServer.Dac.DacServices $connectionString
                    $dacServices.Unregister($Database)
                } catch {
                    Stop-Function -Message "Failed to unpublish SqlWatch DACPAC from $database on $instance." -ErrorRecord $_
                }
            }
        }
    }
}
