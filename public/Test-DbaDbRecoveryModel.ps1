function Test-DbaDbRecoveryModel {
    <#
    .SYNOPSIS
        Validates whether databases are truly operating in their configured recovery model

    .DESCRIPTION
        When you switch a database into FULL recovery model, it will behave like a SIMPLE recovery model until a full backup is taken in order to begin a log backup chain. This function identifies the gap between configured and actual recovery model behavior.

        For FULL recovery databases, the function checks if a log backup chain has been established by examining the last_log_backup_lsn in sys.database_recovery_status. Databases without this value are functionally operating in SIMPLE mode despite being configured for FULL recovery.

        This validation is critical for DBAs who need to ensure point-in-time recovery capabilities are actually available, not just configured. It also allows validation of SIMPLE or BULK_LOGGED recovery models on an instance.

        Inspired by Paul Randal's post (http://www.sqlskills.com/blogs/paul/new-script-is-that-database-really-in-the-full-recovery-mode/)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to test for recovery model validation. Accepts multiple database names and supports wildcards.
        When specified, only these databases will be evaluated instead of all databases on the instance.
        Useful when you need to verify recovery model behavior for specific databases or troubleshoot particular applications.

    .PARAMETER ExcludeDatabase
        Specifies which databases to skip during recovery model validation. Accepts multiple database names and supports wildcards.
        Use this to exclude system databases, test databases, or databases you know are properly configured when testing large instances.

    .PARAMETER RecoveryModel
        Specifies which recovery model to validate against configured settings. Valid values are Full, Simple, or Bulk_Logged.
        Defaults to Full recovery model, which also checks if databases have established a log backup chain for true point-in-time recovery.
        Use Simple or Bulk_Logged when auditing databases that should be configured for those specific recovery models.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DisasterRecovery, Backup
        Author: Claudio Silva (@ClaudioESSilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT

    .LINK
        https://dbatools.io/Test-DbaDbRecoveryModel

    .EXAMPLE
        PS C:\> Test-DbaDbRecoveryModel -SqlInstance sql2005

        Shows all databases where the configured recovery model is FULL and indicates whether or not they are really in FULL recovery model.

    .EXAMPLE
        PS C:\> Test-DbaDbRecoveryModel -SqlInstance . | Where-Object {$_.ActualRecoveryModel -ne "FULL"}

        Only shows the databases that are functionally in 'simple' mode.

    .EXAMPLE
        PS C:\> Test-DbaDbRecoveryModel -SqlInstance sql2008 -RecoveryModel Bulk_Logged | Sort-Object Server  -Descending

        Shows all databases where the configured recovery model is BULK_LOGGED and sort them by server name descending

    .EXAMPLE
        PS C:\> Test-DbaDbRecoveryModel -SqlInstance localhost | Select-Object -Property *

        Shows all of the properties for the databases that have Full Recovery Model

    #>
    [CmdletBinding()]
    [OutputType("System.Collections.ArrayList")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [PSCredential]$SqlCredential,
        [validateSet("Full", "Simple", "Bulk_Logged")]
        [object]$RecoveryModel,
        [switch]$EnableException
    )
    begin {
        if (Test-Bound -ParameterName RecoveryModel -Not) {
            $RecoveryModel = "Full"
        }

        switch ($RecoveryModel) {
            "Full" { $recoveryCode = 1 }
            "Bulk_Logged" { $recoveryCode = 2 }
            "Simple" { $recoveryCode = 3 }
        }

        $sqlRecoveryModel = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
                ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                SERVERPROPERTY('ServerName') AS SqlInstance
                        , d.[name] AS [Database]
                        , d.recovery_model AS RecoveryModel
                        , d.recovery_model_desc AS RecoveryModelDesc
                        , CASE
                            WHEN d.recovery_model = 1 AND drs.last_log_backup_lsn IS NOT NULL THEN 1
                            ELSE 0
                           END AS IsReallyInFullRecoveryModel
                  FROM sys.databases AS d
                    INNER JOIN sys.database_recovery_status AS drs
                       ON d.database_id = drs.database_id
                  WHERE d.recovery_model = $recoveryCode"

        if ($Database) {
            $dblist = $Database -join "','"
            $databasefilter += "AND d.[name] in ('$dblist')"
        }
        if ($ExcludeDatabase) {
            $dblist = $ExcludeDatabase -join "','"
            $databasefilter += "AND d.[name] NOT IN ('$dblist')"
        }

        $sql = "$sqlRecoveryModel $databasefilter"

        Write-Message -Level Debug -Message $sql
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $results = $server.Query($sql)

                if (-not $results) {
                    Write-Message -Level Verbose -Message "Server '$instance' does not have any databases in the $RecoveryModel recovery model."
                }

                foreach ($row in $results) {
                    if (!([bool]$row.IsReallyInFullRecoveryModel) -and $RecoveryModel -eq 'Full') {
                        $ActualRecoveryModel = "SIMPLE"
                    } else {
                        $ActualRecoveryModel = "$($RecoveryModel.ToString().ToUpper())"
                    }

                    [PSCustomObject]@{
                        ComputerName            = $row.ComputerName
                        InstanceName            = $row.InstanceName
                        SqlInstance             = $row.SqlInstance
                        Database                = $row.Database
                        ConfiguredRecoveryModel = $row.RecoveryModelDesc
                        ActualRecoveryModel     = $ActualRecoveryModel
                    } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, ConfiguredRecoveryModel, ActualRecoveryModel
                }
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}