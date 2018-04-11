function Test-DbaRecoveryModel {
    <#
        .SYNOPSIS
            Find if database is really a specific recovery model or not.

        .DESCRIPTION
            When you switch a database into FULL recovery model, it will behave like a SIMPLE recovery model until a full backup is taken in order to begin a log backup chain.

            However, you may also desire to validate if a database is SIMPLE or BULK LOGGED on an instance.

            Inspired by Paul Randal's post (http://www.sqlskills.com/blogs/paul/new-script-is-that-database-really-in-the-full-recovery-mode/)

        .PARAMETER SqlInstance
            The SQL Server instance to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

        .PARAMETER RecoveryModel
            Specifies the type of recovery model you wish to test. By default it will test for FULL Recovery Model.

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
            https://dbatools.io/Test-DbaRecoveryModel

        .EXAMPLE
            Test-DbaRecoveryModel -SqlInstance sql2005

            Shows all databases where the configured recovery model is FULL and indicates whether or not they are really in FULL recovery model.

        .EXAMPLE
            Test-DbaRecoveryModel -SqlInstance . | Where-Object {$_.ActualRecoveryModel -ne "FULL"}

            Only shows the databases that are functionally in 'simple' mode.

        .EXAMPLE
            Test-DbaRecoveryModel -SqlInstance sql2008 -RecoveryModel Bulk_Logged | Sort-Object Server  -Descending

            Shows all databases where the configured recovery model is BULK_LOGGED and sort them by server name descending

        .EXAMPLE
            Test-DbaRecoveryModel -SqlInstance localhost | Select-Object -Property *

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
        [validateSet("Full","Simple","Bulk_Logged")]
        [object]$RecoveryModel,
        [switch]$Detailed,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter Detailed
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Alias Test-DbaFullRecoveryModel

        if(Test-Bound -ParameterName RecoveryModel -Not){
            $RecoveryModel = "Full"
        }

        switch($RecoveryModel){
            "Full"          {$recoveryCode = 1}
            "Bulk_Logged"   {$recoveryCode = 2}
            "Simple"        {$recoveryCode = 3}
        }

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
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 9
            }
            catch {
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
                    }
                    else{
                        $ActualRecoveryModel = "$($RecoveryModel.ToString().ToUpper())"
                    }

                    [PSCustomObject]@{
                        ComputerName   = $row.ComputerName
                        InstanceName   = $row.InstanceName
                        SqlInstance    = $row.SqlInstance
                        Database       = $row.Database
                        ConfiguredRecoveryModel = $row.RecoveryModelDesc
                        ActualRecoveryModel = $ActualRecoveryModel
                    } | Select-DefaultView -Property ComputerName,InstanceName,SqlInstance,Database,ConfiguredRecoveryModel,ActualRecoveryModel
                }
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}