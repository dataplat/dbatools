function Set-DbaDbRecoveryModel {
    <#
    .SYNOPSIS
        Set-DbaDbRecoveryModel sets the Recovery Model.

    .DESCRIPTION
        Set-DbaDbRecoveryModel sets the Recovery Model for user databases.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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

    .PARAMETER InputObject
        A collection of databases (such as returned by Get-DbaDatabase)

    .NOTES
        Tags: RecoveryModel, Database
        Author: Viorel Ciucu (@viorelciucu), https://www.cviorel.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbRecoveryModel

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

        Sets the Recovery Model to Simple for ALL uses databases MODEL database on SQL Server instance sql2014. Runs without asking for confirmation.

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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