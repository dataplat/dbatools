function Get-DbaDbRecoveryModel {
    <#
        .SYNOPSIS 
            Get-DbaDbRecoveryModel displays the Recovery Model.

        .DESCRIPTION
            Get-DbaDbRecoveryModel displays the Recovery Model for all databases. This is the default, you can filter using -Database, -ExcludeDatabase, -RecoveryModel

        .PARAMETER SqlInstance
            The SQL Server instance.

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
            This is a parameter that was included for safety, so you don't accidentally set options on all databases without specifying. Not required by default as we're not changing anything.

        .PARAMETER RecoveryModel
            Filters the output based on Recovery Model. Valid options are 'Simple', 'Full', 'BulkLogged'
            
            Details about the recovery models can be found here: 
            https://docs.microsoft.com/en-us/sql/relational-databases/backup-restore/recovery-models-sql-server

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
			Prompts for confirmation. For example:

			Are you sure you want to perform this action?
			Performing the operation "ALTER DATABASE [model] SET RECOVERY Full" on target "[model] on WERES14224".
            [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):            
            
            Not required by default as we're not changing anything.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Recovery, RecoveryModel, Simple, Full, Bulk, BulkLogged
            Author: Viorel Ciucu (@viorelciucu), https://www.cviorel.com

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaDbRecoveryModel

        .EXAMPLE
            Get-DbaDbRecoveryModel -SqlInstance sql2014 -RecoveryModel BulkLogged -Verbose

            Gets all databases on SQL Server instance sql2014 having RecoveryModel set to BulkLogged

        .EXAMPLE
            Get-DbaDbRecoveryModel -SqlInstance sql2014 -RecoveryModel Simple -Database TestDB

            Gets all databases on SQL Server instance sql2014 having RecoveryModel set to BulkLogged and filters the output for TestDB. If TestDB does not exist on the instance we don't return anythig.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [ValidateSet('Simple', 'Full', 'BulkLogged')]
        [string]$RecoveryModel,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline = $true)]
        [switch][Alias('Silent')]$EnableException
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
                  
            $databases = Get-DbaDatabase -SqlInstance $instance
            
            # filter collection based on -Database/-Exclude parameters
            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }
            
            if ($RecoveryModel) {
                $databases = $databases | Where-Object RecoveryModel -In $RecoveryModel
            }
          
            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Status', 'IsAccessible', 'RecoveryModel',
			'LogReuseWaitStatus', 'Size as SizeMB', 'CompatibilityLevel as Compatibility', 'Collation', 'Owner',
			'LastBackupDate as LastFullBackup', 'LastDifferentialBackupDate as LastDiffBackup',
			'LastLogBackupDate as LastLogBackup'
			
            foreach ($db in $databases) {
                Select-DefaultView -InputObject $db -Property $defaults
            }
        }
    }
}