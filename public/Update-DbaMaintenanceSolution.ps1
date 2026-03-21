function Update-DbaMaintenanceSolution {
    <#
    .SYNOPSIS
        Updates existing Ola Hallengren Maintenance Solution stored procedures to the latest version

    .DESCRIPTION
        Updates the stored procedures for Ola Hallengren's Maintenance Solution on SQL Server instances where it's already installed. This function downloads the latest version from GitHub and replaces only the procedure code, leaving all existing tables, jobs, and configurations intact.

        Use this when you need to get bug fixes or improvements in the maintenance procedures without disrupting your existing backup, integrity check, and index optimization jobs. The function checks for existing procedures before attempting updates and only updates what's currently installed.

        This approach only works when the new procedure versions are compatible with your existing table structures and job configurations. If Ola releases changes that require schema modifications or new tables, you'll need to use Install-DbaMaintenanceSolution for a complete reinstallation instead.

    .PARAMETER SqlInstance
        The target SQL Server instance onto which the Maintenance Solution will be updated.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database containing the existing Ola Hallengren maintenance solution stored procedures. Defaults to master.
        Change this if you installed the maintenance solution in a different database like DBA or Admin.

    .PARAMETER Solution
        Controls which maintenance solution components to update. Valid options are All, Backup, IntegrityCheck, IndexOptimize, or CommandExecute.
        Use this when you only want to update specific procedures instead of the entire solution. Only procedures that already exist will be updated.

    .PARAMETER LocalFile
        Path to a local zip file containing Ola Hallengren's maintenance solution instead of downloading from GitHub.
        Use this in environments without internet access or when you need to deploy a specific version that differs from the latest release.

    .PARAMETER Force
        Forces download of the latest maintenance solution from GitHub even if a cached version exists locally.
        Use this when you want to ensure you're getting the absolute latest version or if the cached version is corrupted.

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

    .OUTPUTS
        PSCustomObject

        Returns one object per maintenance solution procedure updated. The command will attempt to update all specified solution components (or all components if -Solution is not specified), returning status for each attempt.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Solution: The maintenance solution component name (CommandExecute, Backup, IntegrityCheck, or IndexOptimize)
        - Procedure: The name of the stored procedure being updated
        - IsUpdated: Boolean indicating if the procedure was successfully updated
        - Results: Status or error message. Possible values: "Updated", "Procedure not installed", "File not found", or an error object if the update failed

    .EXAMPLE
        PS C:\> Update-DbaMaintenanceSolution -SqlInstance RES14224 -Database DBA

        Updates Ola Hallengren's Solution objects on RES14224 in the DBA database.

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
        $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child 'sql-server-maintenance-solution-main'
        if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
            if ($PSCmdlet.ShouldProcess('MaintenanceSolution', 'Update local cached copy of the software')) {
                try {
                    Save-DbaCommunitySoftware -Software MaintenanceSolution -LocalFile $LocalFile -EnableException
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

            $db = $server.Databases | Where-Object Name -eq $Database
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
            $null = $server | Disconnect-DbaInstance
        }
    }
}