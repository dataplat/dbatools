function Set-DbaRecoveryModel {
    <#
        .SYNOPSIS 
            Set-DbaRecoveryModel sets the Recovery Model.

        .DESCRIPTION
            Set-DbaRecoveryModel sets the Recovery Model for user databases.

        .PARAMETER SqlInstance
            The SQL Server instance. Server version must be SQL Server version XXXX or higher.

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

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

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
            https://dbatools.io/Set-DbaRecoveryModel

        .EXAMPLE
            Set-DbaRecoveryModel -SqlInstance sql2014 -RecoveryModel Full -AllDatabases -Verbose
            
            Sets the Recovery Model to Full for all user databases on SQL Server instance sql2014
            
        .EXAMPLE
            Set-DbaRecoveryModel -SqlInstance sql2014 -RecoveryModel BulkLogged -Database TestDB
            
            Sets the Recovery Model to BulkLogged for database [TestDB] on SQL Server instance sql2014
            
        .EXAMPLE
            Set-DbaRecoveryModel -SqlInstance sql2014 -RecoveryModel Simple -Database TestDB1, TestDB2 -Verbose
            
            Sets the Recovery Model to Simple for databases [TestDB1] and [TestDB2] on SQL Server instance sql2014
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential][System.Management.Automation.CredentialAttribute()]
        $SqlCredential,
        [ValidateSet('Simple', 'Full', 'BulkLogged')]
        [string]$RecoveryModel = '',
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllDatabases,
        [parameter(ValueFromPipeline = $true)]
        [switch][Alias('Silent')]$EnableException
    )
    process {
        foreach ($serverName in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $serverName -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            
            $dbs = @()
            if (!$Database -and !$AllDatabases -and !$ExcludeDatabase) {
                Stop-Function -Message "You must specify -AllDatabases or -Database to continue"
                return
            }
    
            $dbs = Get-DbaDatabase -ServerInstance $serverName | Where-Object {$_.IsSystemObject -ne $true}
            
            # filter collection based on -Databases/-Exclude parameters
            if ($Database) {
                $dbs = $dbs | Where-Object { $Database -contains $_.Name }
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object { $ExcludeDatabase -notcontains $_.Name }
            }
            
            if (!$dbs) {
                Stop-Function -Message "The database you specified does not exist on the server $serverName"
                return
            }

            foreach ($db in $dbs) {
                if ($db.RecoveryModel -eq $RecoveryModel) {
                    Stop-Function -Message "Recovery Model for database $db is already set to $RecoveryModel" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
                else {
                    $db.RecoveryModel = $RecoveryModel;
                    $db.Alter();
                    Write-Message -Level Verbose -Message "Recovery Model set to $RecoveryModel for database $db"
                }   
            }
        }
    }
}