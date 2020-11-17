function New-DbaDatabase {
    <#
    .SYNOPSIS
        Creates a new database

    .DESCRIPTION
        This command creates a new database.

        It allows creation with multiple files, and sets all growth settings to be fixed size rather than percentage growth. The autogrowth settings are obtained from the modeldev file in the model database when not supplied as command line arguments.

        The generated database filenames take the form:

        <db name>_PRIMARY
        <db name>_Log
        <db name>_MainData_1  (Secondary filegroup files)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        The name of the new database or databases to be created.

    .PARAMETER DataFilePath
        The location that data files will be placed, otherwise the default SQL Server data path will be used.

    .PARAMETER LogFilePath
        The location the log file will be placed, otherwise the default SQL Server log path will be used.

    .PARAMETER Collation
        The database collation, if not supplied the default server collation will be used.

    .PARAMETER RecoveryModel
        The recovery model for the database, if not supplied the recovery model from the model database will be used.
        Valid options are: Simple, Full, BulkLogged.

    .PARAMETER Owner
        The login that will be used as the database owner.

    .PARAMETER PrimaryFilesize
        The size in MB for the Primary file. If this is less than the primary file size for the model database, then the model size will be used instead.

    .PARAMETER PrimaryFileGrowth
        The size in MB that the Primary file will autogrow by.

    .PARAMETER PrimaryFileMaxSize
        The maximum permitted size in MB for the Primary File. If this is less than the primary file size for the model database, then the model size will be used instead.

    .PARAMETER LogSize
        The size in MB that the Transaction log will be created.

    .PARAMETER LogGrowth
        The amount in MB that the log file will be set to autogrow by.

    .PARAMETER LogMaxSize
        The maximum permitted size in MB. If this is less than the log file size for the model database, then the model log size will be used instead.

    .PARAMETER SecondaryFileCount
        The number of files to create in the Secondary filegroup for the database.

    .PARAMETER SecondaryFilesize
        The size in MB of the files to be added to the Secondary filegroup. Each file added will be created with this size setting.

    .PARAMETER SecondaryFileMaxSize
        The maximum permitted size in MB for the Secondary data files to grow to. Each file added will be created with this max size setting.

    .PARAMETER SecondaryFileGrowth
        The amount in MB that the Secondary files will be set to autogrow by. Use 0 for no growth allowed. Each file added will be created with this growth setting.

    .PARAMETER DefaultFileGroup
        Sets the default file group. Either primary or secondary.

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
        New-DbaDatabase -SqlInstance sql1 -Name newDb -LogSize 32 -LogMaxSize 512 -PrimaryFilesize 64 -PrimaryFileMaxSize 512 -SecondaryFilesize 64 -SecondaryFileMaxSize 512 -LogGrowth 32 -PrimaryFileGrowth 64 -SecondaryFileGrowth 64

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
        [switch]$EnableException
    )

    begin {
        # do some checks to see if the advanced config settings will be invoked
        if (Test-Bound -ParameterName DataFilePath, DefaultFileGroup, LogFilePath, LogGrowth, LogMaxSize, LogSize, PrimaryFileGrowth, PrimaryFileMaxSize, PrimaryFilesize, SecondaryFileCount, SecondaryFileGrowth, SecondaryFileMaxSize, SecondaryFilesize) {
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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($advancedconfig -and $server.VersionMajor -eq 8) {
                Stop-Function -Message "Advanced configuration options are not available to SQL Server 2000. Aborting creation of database on $instance" -Target $instance -Continue
            }

            # validate the collation
            if ($Collation) {
                $collations = Get-DbaAvailableCollation -SqlInstance $instance

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
                        $primaryfilename = $dbName + "_PRIMARY"
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
                        $logname = $dbName + "_Log"
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
                            $secondaryfilegroupname = $dbName + "_MainData"
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

                    Get-DbaDatabase -SqlInstance $server -Database $dbName
                }
            }
        }
    }
}