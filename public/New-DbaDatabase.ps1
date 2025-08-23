function New-DbaDatabase {
    <#
    .SYNOPSIS
        Creates new SQL Server databases with customizable file layout and growth settings

    .DESCRIPTION
        Creates new databases on SQL Server instances with full control over file placement, sizing, and growth settings. Rather than using T-SQL CREATE DATABASE statements manually, this function provides a structured approach to database creation with built-in best practices.

        The function automatically configures growth settings to use fixed MB increments instead of percentage-based growth, which prevents runaway autogrowth issues in production environments. When specific file sizes aren't provided, it inherits sensible defaults from the model database to ensure new databases start with appropriate baseline configurations.

        Supports creating databases with secondary filegroups and multiple data files for performance optimization, making it useful for both simple development databases and complex production systems that require specific file layouts for optimal I/O distribution.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Specifies the name of the database(s) to create on the SQL Server instance. Accepts multiple database names as an array to create several databases in a single operation. If not provided, creates a database with a randomly generated name like "random-12345".

    .PARAMETER DataFilePath
        Specifies the directory path where database data files (.mdf and .ndf) will be created. Use this when you need to place database files on specific drives for performance or storage management. If not specified, uses the SQL Server instance's default data directory. The function will create the directory if it doesn't exist.

    .PARAMETER LogFilePath
        Specifies the directory path where transaction log files (.ldf) will be created. Best practice is to place log files on separate drives from data files for performance and availability. If not specified, uses the SQL Server instance's default log directory. The function will create the directory if it doesn't exist.

    .PARAMETER Collation
        Specifies the collation for the new database, which determines sorting rules, case sensitivity, and accent sensitivity for string data. Use this when creating databases that need specific language or cultural sorting requirements different from the server default. If not specified, inherits the server's default collation.

    .PARAMETER RecoveryModel
        Sets the recovery model which determines how transaction log backups work and how much data loss is acceptable. Simple recovery model doesn't require log backups but limits point-in-time recovery, Full enables complete point-in-time recovery with log backups, BulkLogged offers a compromise for bulk operations. If not specified, inherits from the model database.

    .PARAMETER Owner
        Specifies which SQL Server login will be assigned as the database owner (dbo). Use this to assign ownership to a specific service account or administrator instead of the default creator. The login must already exist on the SQL Server instance. If not specified, the connecting user becomes the database owner.

    .PARAMETER PrimaryFilesize
        Sets the initial size in MB for the primary data file (.mdf). Use this to create databases with appropriate initial sizing based on expected data volume to reduce autogrowth events. If the specified size is smaller than the model database's primary file, the model size is used instead to maintain minimum requirements.

    .PARAMETER PrimaryFileGrowth
        Specifies the autogrowth increment in MB for the primary data file when it needs more space. Using fixed MB increments prevents runaway percentage-based growth that can cause performance issues and disk space problems in production environments. If not specified, inherits the model database's growth settings.

    .PARAMETER PrimaryFileMaxSize
        Sets the maximum size limit in MB that the primary data file can grow to during autogrowth events. Use this to prevent database files from consuming all available disk space in case of runaway processes or data imports. If set smaller than the initial file size, the initial size becomes the maximum.

    .PARAMETER LogSize
        Sets the initial size in MB for the transaction log file (.ldf). Proper log sizing prevents frequent autogrowth during normal operations which can impact performance. Size the log based on your transaction volume and backup frequency - larger logs for high-activity databases or infrequent log backups. If not specified, uses the model database's log size.

    .PARAMETER LogGrowth
        Specifies the autogrowth increment in MB for the transaction log file when additional space is needed. Fixed MB growth prevents percentage-based growth that can cause performance delays during high-activity periods. Consider setting this to handle your typical transaction volume between log backups. If not specified, uses the model database's growth settings.

    .PARAMETER LogMaxSize
        Sets the maximum size limit in MB for the transaction log file during autogrowth. This prevents transaction logs from consuming all disk space during bulk operations or when log backups are delayed. Consider your available disk space and typical maintenance windows when setting this limit. If set smaller than the initial log size, the initial size becomes the maximum.

    .PARAMETER SecondaryFileCount
        Specifies how many data files to create in the secondary filegroup. Multiple files allow parallel I/O operations which can improve performance for large databases with high activity. Consider your storage configuration and available CPU cores when determining the file count - typically one file per CPU core up to the number of available drives.

    .PARAMETER SecondaryFilesize
        Sets the initial size in MB for each file in the secondary filegroup. All secondary files will be created with this same size. Use this to establish consistent file sizes across the filegroup for balanced I/O distribution. If not specified and secondary files are created, uses the model database's file size.

    .PARAMETER SecondaryFileMaxSize
        Sets the maximum size limit in MB for each secondary data file during autogrowth. This prevents individual files from consuming excessive disk space while allowing controlled growth. All secondary files will use this same maximum size limit to maintain consistency across the filegroup.

    .PARAMETER SecondaryFileGrowth
        Specifies the autogrowth increment in MB for each secondary data file when additional space is needed. All secondary files will use the same growth increment to maintain balanced file sizes. Set to 0 to disable autogrowth for controlled file management. Fixed MB increments provide predictable growth behavior.

    .PARAMETER DefaultFileGroup
        Specifies which filegroup becomes the default for new tables and indexes when no filegroup is explicitly specified. Primary uses the standard PRIMARY filegroup, Secondary uses the created secondary filegroup. Setting the secondary filegroup as default directs new objects to use the optimized multi-file configuration for better performance.

    .PARAMETER DataFileSuffix
        Specifies a custom suffix to append to the primary data file name. The full filename becomes DatabaseName + DataFileSuffix + .mdf. Use this to follow organizational naming conventions or to differentiate between environments (like "_PROD" or "_DEV"). If not specified, no suffix is added.

    .PARAMETER LogFileSuffix
        Specifies the suffix to append to the transaction log file name. The full filename becomes DatabaseName + LogFileSuffix + .ldf. Use this to follow naming conventions that distinguish log files from data files. Defaults to "_log" if not specified, creating files like "MyDatabase_log.ldf".

    .PARAMETER SecondaryDataFileSuffix
        Specifies the suffix used for the secondary filegroup name and its data files. The filegroup becomes DatabaseName + SecondaryDataFileSuffix, and files are named like DatabaseName + SecondaryDataFileSuffix + "_1.ndf". Use descriptive suffixes like "_Data" or "_Indexes" to indicate the intended use of the secondary filegroup.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database
        Author: Matthew Darwin (@evoDBA, naturalselectiondba.wordpress.com)  | Chrissy LeMaire (@cl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDatabase

    .EXAMPLE
        New-DbaDatabase -SqlInstance sql1

        Creates a randomly named database (random-N) on instance sql1

    .EXAMPLE
        New-DbaDatabase -SqlInstance sql1 -Name dbatools, dbachecks

        Creates a database named dbatools and a database named dbachecks on sql1

    .EXAMPLE
        New-DbaDatabase -SqlInstance sql1, sql2, sql3 -Name multidb, multidb2 -SecondaryFilesize 20 -SecondaryFileGrowth 20 -LogSize 20 -LogGrowth 20

        Creates two databases, multidb and multidb2, on 3 instances (sql1, sql2 and sql3) and sets the secondary data file size to 20MB, the file growth to 20MB and the log growth to 20MB for each

    .EXAMPLE
        New-DbaDatabase -SqlInstance sql1 -Name nondefault -DataFilePath M:\Data -LogFilePath 'L:\Logs with spaces' -SecondaryFileCount 2

        Creates a database named nondefault and places data files in in the M:\data directory and log files in "L:\Logs with spaces".

        Creates a secondary group with 2 files in the Secondary filegroup.

    .EXAMPLE
        PS C:\> $databaseParams = @{
        >> SqlInstance             = "sql1"
        >> Name                    = "newDb"
        >> LogSize                 = 32
        >> LogMaxSize              = 512
        >> PrimaryFilesize         = 64
        >> PrimaryFileMaxSize      = 512
        >> SecondaryFilesize       = 64
        >> SecondaryFileMaxSize    = 512
        >> LogGrowth               = 32
        >> PrimaryFileGrowth       = 64
        >> SecondaryFileGrowth     = 64
        >> DataFileSuffix          = "_PRIMARY"
        >> LogFileSuffix           = "_Log"
        >> SecondaryDataFileSuffix = "_MainData"
        >> }
        >> New-DbaDatabase @databaseParams

        Creates a new database named newDb on the sql1 instance and sets the file sizes, max sizes, and growth as specified. The resulting filenames will take the form:

        newDb_PRIMARY
        newDb_Log
        newDb_MainData_1  (Secondary filegroup files)

    #>
    [Cmdletbinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param
    (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias('Database')]
        [string[]]$Name,
        [string]$Collation,
        [ValidateSet('Simple', 'Full', 'BulkLogged')]
        [string]$RecoveryModel,
        [string]$Owner,
        [string]$DataFilePath,
        [string]$LogFilePath,
        [int32]$PrimaryFilesize,
        [int32]$PrimaryFileGrowth,
        [int32]$PrimaryFileMaxSize,
        [int32]$LogSize,
        [int32]$LogGrowth,
        [int32]$LogMaxSize,
        [int32]$SecondaryFilesize,
        [int32]$SecondaryFileGrowth,
        [int32]$SecondaryFileMaxSize,
        [int32]$SecondaryFileCount,
        [ValidateSet('Primary', 'Secondary')]
        [string]$DefaultFileGroup,
        [string]$DataFileSuffix,
        [string]$LogFileSuffix = '_log',
        [string]$SecondaryDataFileSuffix,
        [switch]$EnableException
    )

    begin {
        # do some checks to see if the advanced config settings will be invoked
        if (Test-Bound -ParameterName DataFilePath, DefaultFileGroup, LogFilePath, LogGrowth, LogMaxSize, LogSize, PrimaryFileGrowth, PrimaryFileMaxSize, PrimaryFilesize, SecondaryFileCount, SecondaryFileGrowth, SecondaryFileMaxSize, SecondaryFilesize, DataFileSuffix, LogFileSuffix, SecondaryDataFileSuffix) {
            $advancedconfig = $true
            Write-Message -Message "Advanced data file configuration will be invoked" -Level Verbose
        }
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($advancedconfig -and $server.VersionMajor -eq 8) {
                Stop-Function -Message "Advanced configuration options are not available to SQL Server 2000. Aborting creation of database on $instance" -Target $instance -Continue
            }

            # validate the collation
            if ($Collation) {
                $collations = Get-DbaAvailableCollation -SqlInstance $server

                if ($collations.Name -notcontains $Collation) {
                    Stop-Function -Message "$Collation is not a valid collation on $instance" -Target $instance -Continue
                }
            }

            if (-not (Test-Bound -ParameterName Name)) {
                $Name = "random-$(Get-Random)"
            }

            if (-not (Test-Bound -ParameterName DataFilePath)) {
                $DataFilePath = (Get-DbaDefaultPath -SqlInstance $server).Data
            }

            if (-not (Test-Bound -ParameterName LogFilePath)) {
                $LogFilePath = (Get-DbaDefaultPath -SqlInstance $server).Log
            }

            if (-not (Test-DbaPath -SqlInstance $server -Path $LogFilePath)) {
                try {
                    Write-Message -Message "Creating directory $LogFilePath" -Level Verbose
                    $null = New-DbaDirectory -SqlInstance $server -Path $LogFilePath -EnableException
                } catch {
                    Stop-Function -Message "Error creating log file directory $LogFilePath" -Target $instance -Continue
                }
            }

            if (-not (Test-DbaPath -SqlInstance $server -Path $DataFilePath)) {
                try {
                    Write-Message -Message "Creating directory $DataFilePath" -Level Verbose
                    $null = New-DbaDirectory -SqlInstance $server -Path $DataFilePath -EnableException
                } catch {
                    Stop-Function -Message "Error creating secondary file directory $DataFilePath on $instance" -Target $instance -Continue
                }
            }

            Write-Message -Message "Set local data path to $DataFilePath and local log path to $LogFilePath" -Level Verbose

            foreach ($dbName in $Name) {
                if ($server.Databases[$dbName].Name) {
                    Stop-Function -Message "Database $dbName already exists on $instance" -Target $instance -Continue
                }

                try {
                    Write-Message -Message "Creating smo object for new database $dbName" -Level Verbose
                    $newdb = New-Object Microsoft.SqlServer.Management.Smo.Database($server, $dbName)
                } catch {
                    Stop-Function -Message "Error creating database object for $dbName on server $server" -ErrorRecord $_ -Target $instance -Continue
                }

                if ($Collation) {
                    Write-Message -Message "Setting collation to $Collation" -Level Verbose
                    $newdb.Collation = $Collation
                }

                if ($RecoveryModel) {
                    Write-Message -Message "Setting recovery model to $RecoveryModel" -Level Verbose
                    $newdb.RecoveryModel = $RecoveryModel
                }

                if ($advancedconfig) {
                    try {
                        Write-Message -Message "Creating PRIMARY filegroup" -Level Verbose
                        $primaryfg = New-Object Microsoft.SqlServer.Management.Smo.Filegroup($newdb, "PRIMARY")
                        $newdb.Filegroups.Add($primaryfg)
                    } catch {
                        Stop-Function -Message "Error creating Primary filegroup object" -ErrorRecord $_ -Target $instance -Continue
                    }

                    #add the primary file
                    try {
                        $primaryfilename = $dbName + $DataFileSuffix
                        Write-Message -Message "Creating file name $primaryfilename in filegroup PRIMARY" -Level Verbose

                        # if PrimaryFilesize and PrimaryFileMaxSize were passed in then check the size of the modeldev file; if larger than our $PrimaryFilesize setting use that instead
                        if ($server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size -gt ($PrimaryFilesize * 1024)) {
                            Write-Message -Message "model database modeldev larger than our the PrimaryFilesize so using modeldev size for Primary file" -Level Verbose
                            $PrimaryFilesize = ($server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size / 1024)
                            if ($PrimaryFilesize -gt $PrimaryFileMaxSize) {
                                Write-Message -Message "Resetting Primary File Max size to be the new Primary File Size setting" -Level Verbose
                                $PrimaryFileMaxSize = $PrimaryFilesize
                            }
                        }

                        #create the primary file
                        $primaryfile = New-Object Microsoft.SqlServer.Management.Smo.DataFile($primaryfg, $primaryfilename)
                        $primaryfile.FileName = $DataFilePath + "\" + $primaryfilename + ".mdf"
                        $primaryfile.IsPrimaryFile = $true

                        if (Test-Bound -ParameterName PrimaryFilesize) {
                            $primaryfile.Size = ($PrimaryFilesize * 1024)
                        } else {
                            $primaryfile.Size = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size
                        }
                        if (Test-Bound -ParameterName PrimaryFileGrowth) {
                            $primaryfile.Growth = ($PrimaryFileGrowth * 1024)
                            $primaryfile.GrowthType = "KB"
                        } else {
                            $primaryfile.Growth = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Growth
                            $primaryfile.GrowthType = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].GrowthType
                        }
                        if (Test-Bound -ParameterName PrimaryFileMaxSize) {
                            $primaryfile.MaxSize = ($PrimaryFileMaxSize * 1024)
                        } else {
                            $primaryfile.MaxSize = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].MaxSize
                        }

                        #add the file to the filegroup
                        $primaryfg.Files.Add($primaryfile)
                    } catch {
                        Stop-Function -Message "Error adding file to Primary filegroup" -ErrorRecord $_ -Target $instance -Continue
                    }

                    try {
                        $logname = $dbName + $LogFileSuffix
                        Write-Message -Message "Creating log $logname" -Level Verbose

                        # if LogSize and LogMaxSize were passed in then check the size of the modellog file; if larger than our $LogSize setting use that instead
                        if ($server.Databases["model"].LogFiles["modellog"].Size -gt ($LogSize * 1024)) {
                            Write-Message -Message "model database modellog larger than our the LogSize so using modellog size for Log file size" -Level Verbose
                            $LogSize = ($server.Databases["model"].LogFiles["modellog"].Size / 1024)
                            if ($LogSize -gt $LogMaxSize) {
                                Write-Message -Message "Resetting Log File Max size to be the new Log File Size setting" -Level Verbose
                                $LogMaxSize = $LogSize
                            }
                        }

                        $tlog = New-Object Microsoft.SqlServer.Management.Smo.LogFile($newdb, $logname)
                        $tlog.FileName = $LogFilePath + "\" + $logname + ".ldf"

                        if (Test-Bound -ParameterName LogSize) {
                            $tlog.Size = ($LogSize * 1024)
                        } else {
                            $tlog.Size = $server.Databases["model"].LogFiles["modellog"].Size
                        }
                        if (Test-Bound -ParameterName LogGrowth) {
                            $tlog.Growth = ($LogGrowth * 1024)
                            $tlog.GrowthType = "KB"
                        } else {
                            $tlog.Growth = $server.Databases["model"].LogFiles["modellog"].Growth
                            $tlog.GrowthType = $server.Databases["model"].LogFiles["modellog"].GrowthType
                        }
                        if (Test-Bound -ParameterName LogMaxSize) {
                            $tlog.MaxSize = ($LogMaxSize * 1024)
                        } else {
                            $tlog.MaxSize = $server.Databases["model"].LogFiles["modellog"].MaxSize
                        }

                        #add the log to the db
                        $newdb.LogFiles.Add($tlog)
                    } catch {
                        Stop-Function -Message "Error adding log file to database." -ErrorRecord $_ -Target $instance -Continue
                    }

                    if ($DefaultFileGroup -eq "Secondary" -or (Test-Bound -ParameterName SecondaryFileMaxSize, SecondaryFileGrowth, SecondaryFilesize, SecondaryFileCount)) {
                        #add the Secondary data file group
                        try {
                            $secondaryfilegroupname = $dbName + $SecondaryDataFileSuffix
                            Write-Message -Message "Creating Secondary filegroup $secondaryfilegroupname" -Level Verbose

                            $secondaryfg = New-Object Microsoft.SqlServer.Management.Smo.Filegroup($newdb, $secondaryfilegroupname)
                            $newdb.Filegroups.Add($secondaryfg)
                        } catch {
                            Stop-Function -Message "Error creating Secondary filegroup" -ErrorRecord $_ -Target $instance -Continue
                        }

                        # if SecondaryFilesize and SecondaryFileMaxSize were passed in then check the size of the modeldev file; if larger than our $SecondaryFilesize setting use that instead
                        if ($server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size -gt ($SecondaryFilesize * 1024)) {
                            Write-Message -Message "model database modeldev larger than our the SecondaryFilesize so using modeldev size for the Secondary file" -Level Verbose
                            $SecondaryFilesize = ($server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size / 1024)
                            if ($SecondaryFilesize -gt $SecondaryFileMaxSize) {
                                Write-Message -Message "Resetting Secondary File Max size to be the new Secondary File Size setting" -Level Verbose
                                $SecondaryFileMaxSize = $SecondaryFilesize
                            }
                        }

                        # add the required number of files to the filegroup in a loop
                        $secondaryfgcount = $bail = 0

                        # open a loop while the filecounter is less than the required number of files
                        do {
                            $secondaryfgcount++
                            try {
                                $secondaryfilename = "$($secondaryfilegroupname)_$($secondaryfgcount)"
                                Write-Message -Message "Creating file name $secondaryfilename in filegroup $secondaryfilegroupname" -Level Verbose
                                $secondaryfile = New-Object Microsoft.SQLServer.Management.Smo.Datafile($secondaryfg, $secondaryfilename)
                                $secondaryfile.FileName = $DataFilePath + "\" + $secondaryfilename + ".ndf"

                                if (Test-Bound -ParameterName SecondaryFilesize) {
                                    $secondaryfile.Size = ($SecondaryFilesize * 1024)
                                } else {
                                    $secondaryfile.Size = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size
                                }
                                if (Test-Bound -ParameterName SecondaryFileGrowth) {
                                    $secondaryfile.Growth = ($SecondaryFileGrowth * 1024)
                                    $secondaryfile.GrowthType = "KB"
                                } else {
                                    $secondaryfile.Growth = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Growth
                                    $secondaryfile.GrowthType = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].GrowthType
                                }
                                if (Test-Bound -ParameterName SecondaryFileMaxSize) {
                                    $secondaryfile.MaxSize = ($SecondaryFileMaxSize * 1024)
                                } else {
                                    $secondaryfile.MaxSize = $server.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].MaxSize
                                }

                                $secondaryfg.Files.Add($secondaryfile)
                            } catch {
                                $bail = $true
                                Stop-Function -Message "Error adding file $secondaryfg to $secondaryfilegroupname" -ErrorRecord $_ -Target $instance
                                return
                            }
                        } while ($secondaryfgcount -lt $SecondaryFileCount -or $bail)
                    }
                }

                Write-Message -Message "Creating Database $dbName" -Level Verbose
                if ($PSCmdlet.ShouldProcess($instance, "Creating the database $dbName on instance $instance")) {
                    try {
                        $newdb.Create()
                    } catch {
                        Stop-Function -Message "Error creating Database $dbName on server $instance" -ErrorRecord $_ -Target $instance -Continue
                    }

                    if ($Owner) {
                        Write-Message -Message "Setting database owner to $Owner" -Level Verbose
                        try {
                            $newdb.SetOwner($Owner)
                            $newdb.Refresh()
                        } catch {
                            Stop-Function -Message "Error setting Database Owner to $Owner" -ErrorRecord $_ -Target $instance -Continue
                        }
                    }

                    if ($DefaultFileGroup -eq "Secondary") {
                        Write-Message -Message "Setting default filegroup to $secondaryfilegroupname" -Level Verbose
                        try {
                            $newdb.SetDefaultFileGroup($secondaryfilegroupname)
                        } catch {
                            Stop-Function -Message "Error setting default filegroup to $secondaryfilegroupname" -ErrorRecord $_ -Target $instance -Continue
                        }
                    }

                    Add-TeppCacheItem -SqlInstance $server -Type database -Name $dbName
                    Get-DbaDatabase -SqlInstance $server -Database $dbName
                }
            }
        }
    }
}