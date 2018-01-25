function Set-DbaDbRecoveryModel {
    <#
        .SYNOPSIS
            Set-DbaDbRecoveryModel sets the Recovery Model.

        .DESCRIPTION
            Set-DbaDbRecoveryModel sets the Recovery Model for user databases.

        .PARAMETER SqlInstance
            The target SQL Server instance or instances.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Database
            The database(s) to process - this list is auto-populated from the server. if unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            The database(s) to exclude - this list is auto-populated from the server

        .PARAMETER AllDatabases
            This is a parameter that was included for safety, so you don't accidentally set options on all databases without specifying

        .PARAMETER RecoveryModel
            Recovery Model to be set. Valid options are 'Simple', 'Full', 'BulkLogged'

            Details about the recovery models can be found here:
            https://docs.microsoft.com/en-us/sql/relational-databases/backup-restore/recovery-models-sql-server

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

        .PARAMETER DatabaseCollection
        A collection of databases (such as returned by Get-DbaDatabase)

        .NOTES
            Tags: Recovery, RecoveryModel, Simple, Full, Bulk, BulkLogged
            Author: Viorel Ciucu (@viorelciucu), https://www.cviorel.com

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Set-DbaDbRecoveryModel

        .EXAMPLE
            Set-DbaDbRecoveryModel -SqlInstance sql2014 -RecoveryModel BulkLogged -Database model -Confirm:$true -Verbose

            Sets the Recovery Model to BulkLogged for database [model] on SQL Server instance sql2014. User is requested to confirm the action.

        .EXAMPLE
            Get-DbaDatabase -SqlInstance sql2014 -Database TestDB | Set-DbaDbRecoveryModel -RecoveryModel Simple  -Confirm:$false

            Sets the Recovery Model to Simple for database [TestDB] on SQL Server instance sql2014. Confirmation is not required.

        .EXAMPLE
            Set-DbaDbRecoveryModel -SqlInstance sql2014 -RecoveryModel Simple -Database TestDB -Confirm:$false

            Sets the Recovery Model to Simple for database [TestDB] on SQL Server instance sql2014. Confirmation is not required.

        .EXAMPLE
            Set-DbaDbRecoveryModel -SqlInstance sql2014 -RecoveryModel Simple -AllDatabases -Confirm:$false

            Sets the Recovery Model to Simple for ALL uses databases MODEL database on SQL Server instance sql2014. Runs without asking for confirmation.

        .EXAMPLE
            Set-DbaDbRecoveryModel -SqlInstance sql2014 -RecoveryModel BulkLogged -Database TestDB1, TestDB2 -Confirm:$false -Verbose

            Sets the Recovery Model to BulkLogged for [TestDB1] and [TestDB2] databases on SQL Server instance sql2014. Runs without asking for confirmation.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(Mandatory, ParameterSetName = "Instance")]
        [Alias("ServerInstance", "SqlServer")]
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
        [Microsoft.SqlServer.Management.Smo.Database[]]$DatabaseCollection
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (!$Database -and !$AllDatabases -and !$ExcludeDatabase) {
                Stop-Function -Message "You must specify -AllDatabases or -Database to continue"
                return
            }

            # We need to be able to change the RecoveryModel for model database
            $systemdbs = @("tempdb")
            $databases = $server.Databases | Where-Object { $systemdbs -notcontains $_.Name -and $_.IsAccessible }

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

            $DatabaseCollection += $databases
        }

        foreach ($db in $DatabaseCollection) {
            if ($db.RecoveryModel -eq $RecoveryModel) {
                Stop-Function -Message "Recovery Model for database $db is already set to $RecoveryModel" -Category ConnectionError -Target $instance -Continue
            }
            else {
                $db.RecoveryModel = $RecoveryModel;
                if ($Pscmdlet.ShouldProcess("$db on $instance", "ALTER DATABASE $db SET RECOVERY $RecoveryModel")) {
                    $db.Alter()
                    Write-Message -Level Verbose -Message "Recovery Model set to $RecoveryModel for database $db"
                }
            }
            Get-DbaDbRecoveryModel -SqlInstance $db.Parent -Database $db.name
        }
    }
}
