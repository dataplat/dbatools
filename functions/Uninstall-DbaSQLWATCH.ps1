#ValidationTags#CodeStyle,Messaging,FlowControl,Pipeline#
Function Uninstall-DbaSQLWATCH {
<#
        .SYNOPSIS
            Uninstalls SQLWATCH.

        .DESCRIPTION
            Deletes all user objects, agent jobs, and historical data associated with SQLWATCH.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            Specifies the database to install SQLWATCH into.

        .PARAMETER Confirm
            Prompts to confirm actions

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: SQLWATCH, marcingminski
            Author: marcingminski ()
            Website: https://sqlwatch.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Uninstall-DbaSQLWATCH

        .EXAMPLE
            Uninstall-DbaSQLWATCH -SqlInstance server1 -Database master

            Deletes all user objects, agent jobs, and historical data associated with SQLWATCH from the master database.

        .EXAMPLE
            Install-DbaSQLWATCH -SqlInstance server1\instance1 -Database DBA

            Logs into server1\instance1 with Windows authentication and then deletes all user objects, agent jobs, and historical data associated with SQLWATCH from the DBA database.

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [object]$Database = "master",
        [string]$LocalFile,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {

        # validate database parameter

        # get SQWATCH objects
        $tables = Get-DbaDbTable -SqlInstance $SqlInstance -Database $Database | Where-Object {$PSItem.Name -like "sql_perf_mon_*" } 
        $views = Get-DbaDbView -SqlInstance $SqlInstance -Database $Database | Where-Object {$PSItem.Name -like "vw_sql_perf_mon_*" }
        $sprocs = Get-DbaDbStoredProcedure -SqlInstance $SqlInstance -Database $Database | Where-Object {$PSItem.Name -like "sp_sql_perf_mon_*" }
        $agentJobs = Get-DbaAgentJob -SqlInstance $SqlInstance | Where-Object {$PSItem.Name -like "DBA-PERF-*" }

    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        try {
            Write-PSFMessage -Level Host -Message "Removing SQL Agent jobs."
            $agentJobs | Remove-DbaAgentJob
        }
        catch {
            Stop-Function -Message "Could not remove all agent jobs." -ErrorRecord $_ -Target $instance -Continue
        }

        try {
            Write-PSFMessage -Level Host -Message "Removing stored procedures."
            $dropScript = ""
            $sprocs | ForEach-Object {
                $dropScript += "DROP PROCEDURE $($PSItem.Name);`n"
            }
            if ($dropScript) { 
                Invoke-DbaQuery -SqlInstance $SqlInstance -Database $Database -Query $dropScript 
            }
        } 
        catch {
            Stop-Function -Message "Could not remove all stored procedures." -ErrorRecord $_ -Target $instance -Continue
        }
        
        try {
            Write-PSFMessage -Level Host -Message "Removing views."
            $dropScript = ""
            $views | ForEach-Object {
                $dropScript += "DROP VIEW $($PSItem.Name);`n"
            }
            if ($dropScript) { 
                Invoke-DbaQuery -SqlInstance $SqlInstance -Database $Database -Query $dropScript
            }
        }
        catch {
            Stop-Function -Message "Could not remove all views." -ErrorRecord $_ -Target $instance -Continue
        }
        
        try {
            Write-PSFMessage -Level Host -Message "Removing tables."
            $dropScript = ""
            $tables | ForEach-Object {
                $dropScript += "DROP TABLE $($PSItem.Name);`n"
            }
            if ($dropScript) { 
                Invoke-DbaQuery -SqlInstance $SqlInstance -Database $Database -Query $dropScript
            }
        }
        catch {
            Stop-Function -Message "Could not remove all tables." -ErrorRecord $_ -Target $instance -Continue
        }

    }
    end {}
}