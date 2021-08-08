function Update-DbaMaintenanceSolution {
    <#
    .SYNOPSIS
        Download and Update SQL Server Maintenance Solution created by Ola Hallengren (https://ola.hallengren.com)

    .DESCRIPTION
        This script will download and update the latest version of SQL Server Maintenance Solution created by Ola Hallengren.
        Only the stored procedure will be updated. All tables and jobs will stay untouched.

        So this can only be used until a new version of the procedures need a new version of the tables or jobs.
        In this case you have to completely reinstall the SQL Server Maintenance Solution with Install-DbaMaintenanceSolution.

    .PARAMETER SqlInstance
        The target SQL Server instance onto which the Maintenance Solution will be updated.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database where Ola Hallengren's solution is currently installed. Defaults to master.

    .PARAMETER Solution
        Specifies which portion of the Maintenance solution to update. Valid values are All (full solution), Backup, IntegrityCheck and IndexOptimize.
        Defaults to All, but only existing procedures will be replaced.

    .PARAMETER LocalFile
        Specifies the path to a local file to install Ola's solution from. This *should* be the zip file as distributed by the maintainers.
        If this parameter is not specified, the latest version will be downloaded from https://github.com/olahallengren/sql-server-maintenance-solution

    .PARAMETER Force
        If this switch is enabled, the Ola's solution will be downloaded from the internet even if previously cached.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, OlaHallengren
        Author: Andreas Jordan, @JordanOrdix

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://ola.hallengren.com

    .LINK
         https://dbatools.io/Update-DbaMaintenanceSolution

    .EXAMPLE
        PS C:\> Update-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA

        Updates Ola Hallengren's Solution objects on RES14224 in the DBA database.

    .EXAMPLE
        PS C:\> Install-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA -Solution Backup

        This will update the stored procedure DatabaseBackup only, even if other parts of the solution are also installed.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Internal functions are ignored")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Database = "master",
        [ValidateSet('All', 'Backup', 'IntegrityCheck', 'IndexOptimize', 'CommandExecute')]
        [string[]]$Solution = 'All',
        [string]$LocalFile,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        if ($Solution -contains 'All') {
            $Solution = @('CommandExecute', 'Backup', 'IntegrityCheck', 'IndexOptimize');
        } elseif ($Solution -contains 'CommandExecute') {
            # Take care that CommandExecute is the first procedure to update
            $Solution = @('CommandExecute') + ($Solution | Where-Object { $_ -ne 'CommandExecute' })
        }

        # Do we need a new local cached version of the software?
        $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
        $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child 'sql-server-maintenance-solution-master'
        if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
            if ($PSCmdlet.ShouldProcess('MaintenanceSolution', 'Update local cached copy of the software')) {
                try {
                    Update-DbaLocalCachedSoftware -Software MaintenanceSolution -LocalFile $LocalFile -EnableException
                } catch {
                    Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_
                }
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -NonPooledConnection
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $db = $server.Databases[$Database]
            if ($null -eq $db) {
                Stop-Function -Message "Database $Database not found on $instance. Skipping." -Target $instance -Continue
            }

            $installedProcedures = Get-DbaModule -SqlInstance $server -Database $Database | Where-Object Name -in 'CommandExecute', 'DatabaseBackup', 'DatabaseIntegrityCheck', 'IndexOptimize'

            foreach ($solutionName in $Solution) {
                if ($solutionName -in 'Backup', 'IntegrityCheck') {
                    $procedureName = 'Database' + $solutionName
                } else {
                    $procedureName = $solutionName
                }

                if ($PSCmdlet.ShouldProcess($instance, "Update $solutionName with script $procedureName.sql")) {
                    $output = [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Solution     = $solutionName
                        Procedure    = $procedureName
                        IsUpdated    = $false
                        Results      = $null
                    }

                    if ($procedureName -notin $installedProcedures.Name) {
                        $output.Results = 'Procedure not installed'
                    } else {
                        $file = Get-ChildItem -Path $localCachedCopy -Recurse -File "$procedureName.sql"
                        if ($null -eq $file) {
                            $output.Results = 'File not found'
                        } else {
                            Write-Message -Level Verbose -Message "Updating $procedureName from $($file.FullName)."
                            try {
                                $null = Invoke-DbaQuery -SqlInstance $server -File $file
                                $output.IsUpdated = $true
                                $output.Results = 'Updated'
                            } catch {
                                $output.Results = $_
                            }
                        }
                    }

                    $output
                }
            }

            # Close non-pooled connection as this is not done automatically. If it is a reused Server SMO, connection will be opened again automatically on next request.
            $server.ConnectionContext.Disconnect()
        }
    }
}