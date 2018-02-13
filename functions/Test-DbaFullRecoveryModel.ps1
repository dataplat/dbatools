function Test-DbaFullRecoveryModel {
    <#
        .SYNOPSIS
            Find if database is really in the Full recovery model or not.

        .DESCRIPTION
            When you switch a database into FULL recovery model, it will behave like a SIMPLE recovery model until a full backup is taken in order to begin a log backup chain. This state is also known as 'pseudo-Simple'.

            Inspired by Paul Randal's post (http://www.sqlskills.com/blogs/paul/new-script-is-that-database-really-in-the-full-recovery-mode/)

        .PARAMETER SqlInstance
            The SQL Server instance to connect to.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Database
            Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

        .PARAMETER Detailed
            Output all properties, will be deprecated in 1.0.0 release.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: DisasterRecovery, Backup
            Author: Claudio Silva (@ClaudioESSilva)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Test-DbaFullRecoveryModel

        .EXAMPLE
            Test-DbaFullRecoveryModel -SqlInstance sql2005

            Shows all databases where the configured recovery model is FULL and indicates whether or not they are really in FULL recovery model.

        .EXAMPLE
            Test-DbaFullRecoveryModel -SqlInstance . | Where-Object {$_.ActualRecoveryModel -ne "FULL"}

            Only shows the databases that are in 'pseudo-simple' mode.

        .EXAMPLE
            Test-DbaFullRecoveryModel -SqlInstance sql2008 | Sort-Object Server, ActualRecoveryModel -Descending

            Shows all databases where the configured recovery model is FULL and indicates whether or not they are really in FULL recovery model. The Sort-Object will cause the databases in 'pseudo-simple' mode to show first.
        
        .EXAMPLE
            Test-DbaFullRecoveryModel -SqlInstance localhost | Select-Object -Property *

            Shows all of the properties for the databases that have Full Recovery Model
    #>
    [CmdletBinding()]
    [OutputType("System.Collections.ArrayList")]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [PSCredential]$SqlCredential,
        [switch]$Detailed,
        [switch][Alias('Silent')]
        $EnableException
    )
    begin {
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter Detailed
        
        $sqlRecoveryModel = "SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
                ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                SERVERPROPERTY('ServerName') AS SqlInstance
                        , d.[name] AS [Database]
                        , d.recovery_model AS RecoveryModel
                        , d.recovery_model_desc AS RecoveryModelDesc
                        , CASE
                            WHEN d.recovery_model = 1 AND drs.last_log_backup_lsn IS NOT NULL THEN 1
                            ELSE 0
                           END AS IsReallyInFullRecoveryModel
                  FROM sys.databases AS D
                    INNER JOIN sys.database_recovery_status AS drs
                       ON D.database_id = drs.database_id
                  WHERE d.recovery_model = 1"
        
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
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            
            try {
                $recoverymodel = $server.Query($sql)
                
                if (-not $recoverymodel) {
                    Write-Message -Level Verbose -Message "Server '$instance' does not have any databases in FULL recovery model."
                }
                
                foreach ($row in $recoverymodel) {
                    if (!([bool]$row.IsReallyInFullRecoveryModel)) {
                        $notes = "Database is still in SIMPLE recovery model until a full database backup is taken."
                        $ActualRecoveryModel = "pseudo-SIMPLE"
                    }
                    else {
                        $notes = $null
                        $ActualRecoveryModel = "FULL"
                    }
                    
                    [PSCustomObject]@{
                        ComputerName   = $row.ComputerName
                        InstanceName   = $row.InstanceName
                        SqlInstance    = $row.SqlInstance
                        Database       = $row.Database
                        ConfiguredRecoveryModel = $row.RecoveryModelDesc
                        ActualRecoveryModel = $ActualRecoveryModel
                        Notes          = $notes
                    } | Select-DefaultView -ExcludeProperty Notes
                }
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}