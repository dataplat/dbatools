function Set-DbaDbRecoveryModel {
    <#
    .SYNOPSIS
        Changes the recovery model for specified databases on SQL Server instances.

    .DESCRIPTION
        Changes the recovery model setting for one or more databases, allowing you to switch between Simple, Full, and BulkLogged recovery modes. This is commonly used when preparing databases for different backup strategies, reducing transaction log growth in development environments, or configuring production databases for point-in-time recovery. The function excludes tempdb and database snapshots automatically, and requires explicit database specification for safety.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to change the recovery model for. Accepts database names as strings or wildcard patterns.
        Use this when you need to target specific databases instead of all databases on the instance. Required unless using -AllDatabases.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip when changing recovery models. Useful when combined with -AllDatabases to exclude specific databases.
        Commonly used to exclude databases that should maintain their current recovery model for operational reasons.

    .PARAMETER AllDatabases
        Required switch when you want to change the recovery model for all databases on the instance.
        This safety parameter prevents accidentally modifying all databases without explicit confirmation. Automatically excludes tempdb and database snapshots.

    .PARAMETER RecoveryModel
        Sets the recovery model for the specified databases. Choose Simple for minimal transaction log usage in development environments, Full for production databases requiring point-in-time recovery, or BulkLogged for bulk operations with reduced logging.
        This change affects backup strategy requirements and transaction log growth patterns for the target databases.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        Prompts for confirmation. For example:

        Are you sure you want to perform this action?
        Performing the operation "ALTER DATABASE [model] SET RECOVERY Full" on target "[model] on WERES14224".
        [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase or similar commands through the pipeline.
        Use this when you need to apply recovery model changes to a filtered set of databases based on specific criteria like size, last backup date, or other properties.

    .NOTES
        Tags: RecoveryModel, Database
        Author: Viorel Ciucu (@viorelciucu), cviorel.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbRecoveryModel

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Database

        Returns one SMO Database object for each database where the recovery model was set. The returned objects show the updated database with the new recovery model applied.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: Database name
        - Status: Current database status (EmergencyMode, Normal, Offline, Recovering, RecoveryPending, Restoring, Standby, Suspect)
        - IsAccessible: Boolean indicating if the database is currently accessible
        - RecoveryModel: Database recovery model (Full, Simple, or BulkLogged) - this will be the newly set value
        - LastFullBackup: DateTime of the most recent full backup
        - LastDiffBackup: DateTime of the most recent differential backup
        - LastLogBackup: DateTime of the most recent transaction log backup

        Note: The output is the result of Get-DbaDbRecoveryModel called for each updated database. When the recovery model is already set to the specified value, an error is issued and no output is returned for that database. When -WhatIf is used, no output objects are returned.

        All other properties from the underlying SMO Database object remain accessible via Select-Object * even though only the properties listed above are displayed by default.

    .EXAMPLE
        PS C:\> Set-DbaDbRecoveryModel -SqlInstance sql2014 -RecoveryModel BulkLogged -Database model -Confirm:$true -Verbose

        Sets the Recovery Model to BulkLogged for database [model] on SQL Server instance sql2014. User is requested to confirm the action.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2014 -Database TestDB | Set-DbaDbRecoveryModel -RecoveryModel Simple  -Confirm:$false

        Sets the Recovery Model to Simple for database [TestDB] on SQL Server instance sql2014. Confirmation is not required.

    .EXAMPLE
        PS C:\> Set-DbaDbRecoveryModel -SqlInstance sql2014 -RecoveryModel Simple -Database TestDB -Confirm:$false

        Sets the Recovery Model to Simple for database [TestDB] on SQL Server instance sql2014. Confirmation is not required.

    .EXAMPLE
        PS C:\> Set-DbaDbRecoveryModel -SqlInstance sql2014 -RecoveryModel Simple -AllDatabases -Confirm:$false

        Sets the Recovery Model to Simple for ALL user and system databases (except TEMPDB) on SQL Server instance sql2014. Runs without asking for confirmation.

    .EXAMPLE
        PS C:\> Set-DbaDbRecoveryModel -SqlInstance sql2014 -RecoveryModel BulkLogged -Database TestDB1, TestDB2 -Confirm:$false -Verbose

        Sets the Recovery Model to BulkLogged for [TestDB1] and [TestDB2] databases on SQL Server instance sql2014. Runs without asking for confirmation.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(Mandatory, ParameterSetName = "Instance")]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [ValidateSet('Simple', 'Full', 'BulkLogged')]
        [string]$RecoveryModel,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllDatabases,
        [switch]$EnableException,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Pipeline")]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (!$Database -and !$AllDatabases -and !$ExcludeDatabase) {
                Stop-Function -Message "You must specify -AllDatabases or -Database to continue"
                return
            }

            # We need to be able to change the RecoveryModel for model database
            $systemdbs = @("tempdb")
            $databases = $server.Databases | Where-Object { $systemdbs -notcontains $_.Name -and $_.IsAccessible -and -Not($_.IsDatabaseSnapshot) }

            # filter collection based on -Database/-Exclude parameters
            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }

            if (!$databases) {
                Stop-Function -Message "The database(s) you specified do not exist on the instance $instance."
                return
            }

            $InputObject += $databases
        }

        foreach ($db in $InputObject) {
            if ($db.RecoveryModel -eq $RecoveryModel) {
                Stop-Function -Message "Recovery Model for database $db is already set to $RecoveryModel" -Category ConnectionError -Target $instance -Continue
            } else {
                if ($Pscmdlet.ShouldProcess("$db on $instance", "ALTER DATABASE $db SET RECOVERY $RecoveryModel")) {
                    $db.RecoveryModel = $RecoveryModel
                    $db.Alter()
                    Write-Message -Level Verbose -Message "Recovery Model set to $RecoveryModel for database $db"
                }
            }
            Get-DbaDbRecoveryModel -SqlInstance $db.Parent -Database $db.name
        }
    }
}