Function Uninstall-DbaSqlWatch {
    <#
    .SYNOPSIS
        Completely removes SqlWatch monitoring solution from a SQL Server instance

    .DESCRIPTION
        Performs a complete uninstallation of the SqlWatch performance monitoring solution by removing all associated database objects, SQL Agent jobs, and historical data. This includes dropping all SqlWatch tables (containing performance metrics history), views, stored procedures, functions, Extended Events sessions, Service Broker components, assemblies, and user-defined table types. The function also unpublishes the SqlWatch DACPAC registration to ensure clean removal. Use this when decommissioning SqlWatch or preparing for a fresh installation after configuration issues.

    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database containing the SqlWatch installation to remove. Defaults to master.
        Use this when SqlWatch was installed in a database other than the default master database.

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
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if ($PSEdition -eq 'Core') {
            Stop-Function -Message "PowerShell Core is not supported, please use Windows PowerShell."
            return
        }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # get SqlWatch objects
            $tables = Get-DbaDbTable -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "sqlwatch_*" -or $PSItem.Name -like "dbachecks*" -or $PSItem.Name -eq "__RefactorLog" } | Sort-Object $PSItem.createdate -Descending
            $views = Get-DbaDbView -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "vw_sqlwatch_*" } | Sort-Object $PSItem.createdate -Descending
            $sprocs = Get-DbaDbStoredProcedure -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "usp_sqlwatch_*" -or $PSItem.Name -like "Stream*" } | Sort-Object $PSItem.createdate -Descending
            $funcs = Get-DbaDbUdf -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "ufn_sqlwatch_*" -or $PSItem.Name -like "Get*" -or $PSItem.Name -like "Read*" -and $PSItem.Name -notin "ufn_sqlwatch_get_threshold_comparator", "ufn_sqlwatch_clean_sql_text" } | Sort-Object $PSItem.createdate
            $funcs += Get-DbaDbUdf -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -in "ufn_sqlwatch_get_threshold_comparator", "ufn_sqlwatch_clean_sql_text" }
            $agentJobs = Get-DbaAgentJob -SqlInstance $server | Where-Object { $PSItem.Name -like "SqlWatch-*" }
            $XESessions = Get-DbaXESession -SqlInstance $server | Where-Object { $PSItem.Name -like "SQLWATCH_*" }
            $Assemblies = Get-DbaDbAssembly -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "SqlWatch*" }
            $TableTypes = Get-DbaDbUserDefinedTableType -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "utype_*" }
            $BrokerQueues = Get-DbaDbServiceBrokerQueue -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "sqlwatch_*" }
            $BrokerServices = Get-DbaDbServiceBrokerService -SqlInstance $server -Database $Database | Where-Object { $PSItem.Name -like "sqlwatch_*" }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch SQL Agent jobs")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SQL Agent jobs from $server."
                    $agentJobs | Remove-DbaAgentJob -Confirm:$false | Out-Null
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch Agent Jobs on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch stored procedures")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch stored procedures from $database on $server."
                    if ($sprocs) {
                        $sprocs | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch stored procedures from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch views")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch views from $database on $server."
                    if ($views) {
                        $views | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch views from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch functions")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch functions from $database on $server."
                    if ($funcs) {
                        $funcs | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch functions from $database on $server." -ErrorRecord $_ -Target $server -Continue
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
                    if ($tables) {
                        $tables | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch tables from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch Assemblies")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch assemblies from $database on $server."
                    if ($Assemblies) {
                        $Assemblies | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch assemblies from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch Table Types")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch Table Types from $database on $server."
                    if ($TableTypes) {
                        $TableTypes | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch Table Types from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch Service Broker Services")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch service broker services from $database on $server."
                    if ($BrokerServices) {
                        $BrokerServices | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch broker services from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch Service Broker Queues")) {
                try {
                    Write-Message -Level Verbose -Message "Removing SqlWatch service broker queues from $database on $server."
                    if ($BrokerQueues) {
                        $BrokerQueues | ForEach-Object { $PSItem.Drop() }
                    }
                } catch {
                    Stop-Function -Message "Could not remove all SqlWatch broker queues from $database on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Removing SqlWatch XE Sessions")) {
                try {
                    if ($XESessions) {
                        Remove-DbaXESession -SqlInstance $Server -Session $XESessions.Name -Confirm:$false
                    }
                } catch {
                    Stop-Function -Message "Could not remove all XE Session for SqlWatch on $server." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($PSCmdlet.ShouldProcess($server, "Unpublishing DACPAC")) {
                try {
                    Write-Message -Level Verbose -Message "Unpublishing SqlWatch DACPAC from $database on $server."
                    $connectionString = $server.ConnectionContext.ConnectionString | Convert-ConnectionString
                    $dacServices = New-Object Microsoft.SqlServer.Dac.DacServices $connectionString
                    $dacServices.Unregister($Database)
                } catch {
                    Stop-Function -Message "Failed to unpublish SqlWatch DACPAC from $database on $server." -ErrorRecord $_
                }
            }
        }
    }
}