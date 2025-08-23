function Get-DbaDbRecoveryModel {
    <#
    .SYNOPSIS
        Retrieves database recovery model settings and backup history information from SQL Server instances.

    .DESCRIPTION
        Retrieves recovery model configuration for databases along with their last backup dates, which is essential for backup strategy planning and compliance auditing. DBAs use this to identify databases with inappropriate recovery models for their business requirements, troubleshoot transaction log growth issues, and ensure backup policies align with recovery model settings. The function shows whether databases are accessible and when their last full, differential, and transaction log backups occurred, making it valuable for both routine maintenance and disaster recovery planning.

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

    .PARAMETER RecoveryModel
        Filters the output based on Recovery Model. Valid options are Simple, Full and BulkLogged

        Details about the recovery models can be found here:
        https://docs.microsoft.com/en-us/sql/relational-databases/backup-restore/recovery-models-sql-server

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Recovery, RecoveryModel, Backup
        Author: Viorel Ciucu (@viorelciucu), cviorel.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbRecoveryModel

    .EXAMPLE
        PS C:\> Get-DbaDbRecoveryModel -SqlInstance sql2014 -RecoveryModel BulkLogged -Verbose

        Gets all databases on SQL Server instance sql2014 having RecoveryModel set to BulkLogged.

    .EXAMPLE
        PS C:\> Get-DbaDbRecoveryModel -SqlInstance sql2014 -Database TestDB

        Gets recovery model information for TestDB. If TestDB does not exist on the instance nothing is returned.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet('Simple', 'Full', 'BulkLogged')]
        [string[]]$RecoveryModel,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )
    begin {
        $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Status', 'IsAccessible', 'RecoveryModel',
        'LastBackupDate as LastFullBackup', 'LastDifferentialBackupDate as LastDiffBackup',
        'LastLogBackupDate as LastLogBackup'
    }
    process {
        $params = @{
            SqlInstance     = $SqlInstance
            SqlCredential   = $SqlCredential
            Database        = $Database
            ExcludeDatabase = $ExcludeDatabase
            EnableException = $EnableException
        }

        if ($RecoveryModel) {
            Get-DbaDatabase @params | Where-Object RecoveryModel -in $RecoveryModel | Where-Object IsAccessible | Select-DefaultView -Property $defaults
        } else {
            Get-DbaDatabase @params | Select-DefaultView -Property $defaults
        }
    }
}