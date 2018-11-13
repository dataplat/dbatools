function New-DbaDatabase {
    <#
    .SYNOPSIS
        Creates a new database

    .DESCRIPTION
        New-DbaDatabase creates a new database with a single user filegroup, and the PRIMARY filegroup reserved for system objects.
        It allows creation with multiple files, and sets all growth settings to be fixed size rather than percentage growth.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Alternatively, you can provide a ConnectionString.

    .PARAMETER SqlCredential
        Allows you to login to servers using alternative logins instead Integrated, accepts Credential object created by Get-Credential

    .PARAMETER Name
        The name of the new database to be created.

    .PARAMETER NumberOfFilesInUserFilegroup
        The number of files to create in the user filegroup for the database. Default is 1.

    .PARAMETER DefaultDataFilePath
        The location that data files will be placed if UseDefaultFileLocations is set to false.

    .PARAMETER DefaultLogFilePath
        The location the log file will be placed if UseDefaultFileLocations is set to False.

    .PARAMETER Collation
        The Database collation, if not supplied the default server collation will be used.

    .PARAMETER RecoveryModel
        The recovery model for the database, if not supplied the recovery model from the Model database will be used.

    .PARAMETER Owner
        The login that will be used as the database owner, if not supplied Sa wil be used.

    .PARAMETER UserDataFileSize
        The size in MB of the files to be added to the user filegroup. Each file added will be created with this size setting.

    .PARAMETER UserDataFileMaxSize
        The maximum permitted size in MB for the user data files to grow to. Each file added will be created with this max size setting.

    .PARAMETER UserDataFileGrowth
        The amount in MB that the user files will be set to autogrow by. Use 0 for no growth allowed. Each file added will be created
        with this growth setting.

    .PARAMETER LogSize
        The size in MB that the Transaction log will be created.

    .PARAMTER LogGrowth
        The amount in MB that the log file will be set to autogrow by.

    .PARAMETER PrimaryFileSize
        The size in MB for the Primary file. If this is less than the primary file size for the Model database, then the Model size will be used
        instead. Default is 10MB.

    .PARAMETER PrimaryFileGrowth
        The size in MB that the Primary file will autogrow by. Default is 10MB

    .PARAMETER PrimaryFileMaxSize
        The maximum permitted size in MB for the Primary File. If this is less the primary file size for the Model database, then the Model size
        will be used instead.

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database
        Author: Matthew Darwin (@evoDBA, naturalselectiondba.wordpress.com)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
    
    .LINK
        https://dbatools.io/New-DbaDatabase

    .EXAMPLE
        New-DbaDatabase -SqlInstance sql1 -Name TestDatabase -UserDataFileSize 128 -UserDataFileMaxSize 1024 -UserDataFileGrowth 128  -LogSize 128 -LogGrowth 128
    
        Minimum required parameters; creates a database named TestDatabase on instance sql1 with a user filegroup with a single file of 128MB

    .EXAMPLE
        New-DbaDatabase -SqlInstance sql1, sql2, sql3 -Name 'MultiDatabaseTest' -UserDataFileSize 20 -UserDataFileGrowth 20 `
        -LogSize 20 -LogGrowth 20
        Creates a database named MultiDatabaseTest on instances sql1,sql2 and sql3

    .EXAMPLE
        New-DbaDatabase -SqlInstance sql1 -Name 'NonDefaultLocationTest' -NumberFilesInUserFilegroup 2 -$UseDefaultFileLocations $False `
        -DefaultDataFilePath "C:\DBATools" -DefaultLogFilePath "C:\DBATools"
        Creates a database named DefaultLogFilePath in the C:\DBATools directory, with 2 files in the user filegroup.

    #>

    [cmdletbinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    Param
    (
        # set variables for the database
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Name,
        [double]$NumberOfFilesInUserFilegroup = 1,
        # optional db variables
        [switch]$UseDefaultFileLocations,
        [switch]$DefaultDataFilePath,
        [string]$DefaultLogFilePath,
        [string]$Collation,
        [string]$RecoveryModel,
        [string]$Owner,
        #set the user data size, maxsize and growth
        [double]$UserDataFileSize,
        [double]$UserDataFileMaxSize,
        [double]$UserDataFileGrowth, # use 0 for no growth
        #set the log size and growth
        [double]$LogSize,
        [double]$LogGrowth,
        #set the primary file size in MB (will be converted to kb later)
        [double]$PrimaryFileSize = 10,
        [double]$PrimaryFileGrowth = 10,
        [double]$PrimaryFileMaxSize = 100,
        [switch]$Force,
        [switch]$EnableException
    )
    
    begin {
        $UseDefaultFileLocations = $true
        #Check file directories passed in if not using defaults
        if ($UseDefaultFileLocations -eq $false -and ($DefaultDataFilePath -eq $Null -or $DefaultLogFilePath -eq $Null)) {
            Stop-Function -Message "Non Default file locations selected, but are not supplied" -Category InvalidData -ErrorRecord $_
            return
        }

        #Check that the user data file max size is greater than the user data file size
        if ($UserDataFileSize -gt $UserDataFileMaxSize) {
            Stop-Function -Message "UserDataFilesize of $UserDataFileSize is greater than the UserFileMaxSize setting of $UserDataFileMaxSize" -Category InvalidData `
                -ErrorRecord $_
        }

        #Check that the user data file max size is greater than the user file growth
        if ($UserDataFileGrowth -gt $UserDataFileGrowth) {
            Stop-Function -Message "UserDataFileGrowth of $UserDataFileGrowth is greater than the UserFileMaxSize setting of $UserDataFileMaxSize" -Category InvalidData `
                -ErrorRecord $_
        }

        #Check that the primary data file max size is greater than the primary data file size
        if ($PrimaryFileSize -gt $PrimaryFileMaxSize) {
            Stop-Function -Message "PrimaryFilesize of $PrimaryFileSize is greater than the PrimaryFileMaxSize setting of $PrimaryFileMaxSize" -Category InvalidData `
                -ErrorRecord $_
        }

        #Check that the user data file max size is greater than the user file growth
        if ($PrimaryFileGrowth -gt $PrimaryFileGrowth) {
            Stop-Function -Message "PrimaryFileGrowth of $PrimaryFileGrowth is greater than the PrimaryFileMaxSize setting of $PrimaryFileMaxSize" -Category InvalidData `
                -ErrorRecord $_
        }
    }


    process {

        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            
            #check to see if the database already exists.
            if ($server.Databases[$Name].Name -ne $Null) {
                Stop-Function -Message "Database $Name already exists on $instance" -Target $instance -Continue
            }

            # if we are using the default file locations, get them from the server
            if ($UseDefaultFileLocations -eq $true) {
                #get the default file locations; if the master is in the default location we use that path as the default file will not be set
                $LocalDataDrive = if ($server.DefaultFile -eq [DBNULL]::value)
                {$server.MasterDBPath}
                else
                {$server.DefaultFile}
                $LocalLogDrive = $server.DefaultLog
            } elseif ($UseDefaultFileLocations -eq $false) {
                $LocalDataDrive = $DefaultDataFilePath
                $LocanewlLogDrive = $DefaultLogFilePath
            }

            #create the file locations if they do not already exist
            try {
                if ((test-path -path $LocalDataDrive) -eq $false) {
                    write-message -message "Creating directory $LocalDataDrive" -level verbose
                    new-item -path $LocalDataDrive -ItemType Directory
                }
            } catch {
                Stop-Function -Message "Error creating user file directory $LocalDataDrive" -Target $instance -Continue
            }

            #create the log file locations if they do not already exist
            try {
                if ((test-path -path $LocalLogDrive) -eq $false) {
                    write-message -message "Creating directory $LocalLogDrive" -level verbose
                    new-item -path $LocalLogDrive -ItemType Directory
                }
            } catch {
                Stop-Function -Message "Error creating log file directory $LocalLogDrive" -Target $instance -Continue
            }

            #output message in verbose mode
            Write-Message -message "Set local Data drive to $LocalDataDrive and local log drive to $LocalLogDrive" -level verbose

            #create the new db object

            try {
                write-message -message "Creating smo object for new database $Name" -level verbose
                $NewDB = New-Object Microsoft.SqlServer.Management.Smo.Database($server, $Name)
            } catch {
                Stop-Function -Message "Error creating database object for $Name on server $server" -ErrorRecord $_ -Target $instance -Continue
            }

            #add the primary filegroup and a primary file
            try {
                write-message -message "Creating PRIMARY filegroup" -level Verbose
                $PrimaryFG = new-object Microsoft.SqlServer.Management.Smo.Filegroup($NewDB, "PRIMARY")
                $NewDB.Filegroups.Add($PrimaryFG)
            } catch {
                Stop-Function -Message "Error creating Primary filegroup object" -ErrorRecord $_ -Target $instance -Continue
            }

            #add the primary file
            try {
                $PrimaryFileName = $Name + "_PRIMARY"
                Write-Message -message "Creating file name $PrimaryFileName in filegroup PRIMARY" -level verbose

                #check the size of the modeldev file; if larger than our $PrimaryFileSize setting use that instead
                if ($server.Databases["Model"].FileGroups["PRIMARY"].Files["modeldev"].Size -gt ($PrimaryFileSize * 1024)) {
                    write-message -message "Model database modeldev larger than our the PrimaryFileSize so using modeldev size for Primary file" -level verbose
                    $PrimaryFileSize = ($server.Databases["Model"].FileGroups["PRIMARY"].Files["modeldev"].Size / 1024)
                    if ($PrimaryFileSize -gt $PrimaryFileMaxSize) {
                        write-message -message "Resetting Primary File Max size to be the new Primary File Size setting" -level verbose
                        $PrimaryFileMaxSize = $PrimaryFileSize
                    }

                }

                #create the filegroup object
                $PrimaryFile = new-object Microsoft.SqlServer.Management.Smo.DataFile($PrimaryFG, $PrimaryFileName)
                $PrimaryFile.FileName = $LocalDataDrive + "\" + $PrimaryFileName + ".mdf"
                $PrimaryFile.Size = ($PrimaryFileSize * 1024)
                $PrimaryFile.GrowthType = "KB"
                $PrimaryFile.Growth = ($PrimaryFileGrowth * 1024)
                $PrimaryFile.MaxSize = ($PrimaryFileMaxSize * 1024)
                $PrimaryFile.IsPrimaryFile = "true"
                #add the file to the filegroup
                $PrimaryFG.Files.Add($PrimaryFile)
            } catch {
                Stop-Function -Message "Error adding file to Primary filegroup" -ErrorRecord $_ -Target $instance -Continue
            }

            #add the user data file group
            try {
                $UserFilegroupName = $Name + "_MainData"
                write-Message -message "Creating user filegroup $UserFileGroupName" -level Verbose

                $UserFG = new-object Microsoft.SqlServer.Management.Smo.Filegroup($NewDB, $UserFilegroupName)
                $NewDB.Filegroups.Add($UserFG)
            } catch {
                Stop-Function -Message "Error creating user filegroup" -ErrorRecord $_ -Target $instance -Continue
            }

            #add the required number of files to the filegroup in a loop
            #set the filecounter
            $FileCounter = 1

            #open a loop while the filecounter is less than the required number of files
            While ($FileCounter -le $NumberOfFilesInUserFilegroup) {
                #Set the file name
                try {
                    $UserFileName = $UserFileGroupName + "_" + [string]$FileCounter
                    Write-Message -message "Creating file name $UserFileName in filegroup $UserFileGroupName" -Level Verbose
                    #create the smo object for the file
                    $UserFile = new-object Microsoft.SQLServer.Management.Smo.Datafile($UserFG, $UserFileName)
                    $UserFile.FileName = $LocalDataDrive + "\" + $UserFileName + ".ndf"
                    $UserFile.Size = ($UserDataFileSize * 1024)
                    $UserFile.GrowthType = "KB"
                    $UserFile.Growth = ($UserDataFileGrowth * 1024)
                    $UserFile.MaxSize = ($UserDataFileMaxSize * 1024)
                    #add the file to the filegroup
                    $UserFG.Files.Add($UserFile)
                } catch {
                    Stop-Function -Message "Error adding file $FileCounter to $UserFileGroupName" -ErrorRecord $_ -Target $instance -Continue
                }
                #increment the file counter
                $FileCounter = $FileCounter + 1
            }

            #now create the log file
            try {
                $LogName = $Name + "_Log"
                write-message -message "Creating log $LogName" -level verbose

                #check the size of the modellog file; if larger than our $LogSize setting use that instead
                if ($server.Databases["Model"].LogFiles["modellog"].Size -gt ($LogSize * 1024)) {
                    write-message -message "Model database modellog larger than our the LogSize so using modellog size for Log file size" -level verbose
                    $LogSize = ($server.Databases["Model"].LogFiles["modellog"].Size / 1024)

                }

                #add the log to the db
                $TLog = new-object Microsoft.SqlServer.Management.Smo.LogFile($NewDB, $LogName)
                $TLog.FileName = $LocalLogDrive + "\" + $LogName + ".ldf"
                $TLog.Size = ($LogSize * 1024)
                $TLog.GrowthType = "KB"
                $TLog.Growth = ($LogGrowth * 1024)
                #add the log to the db
                $NewDB.LogFiles.Add($TLog)
            } catch {
                Stop-Function -Message "Error adding log file to database." -ErrorRecord $_ -Target $instance -Continue
            }

            #set database settings; collation, owner, recovery model

            #set the collation
            if ($Collation.Length -eq 0) {
                Write-Message -message "Using default server collation" -level verbose
            } else {
                write-message -message "Setting collation to $Collation" -level verbose
                $NewDB.Collation = $Collation
            }

            #set the recovery model
            if ($RecoveryModel.Length -eq 0) {
                write-message -message "Using default recovery model from the Model database" -level verbose
            } else {
                Write-Message -message "Setting recovery model to $RecoveryModel" -level Verbose
                $NewDB.RecoveryModel = $RecoveryModel
            }

            #we should now be able to create the db, and run any other config settings afterwards
            Write-Message -message "Creating Database $Name" -level verbose
            if ($PSCmdlet.ShouldProcess($instance, "Creating the database $Name on instance $instance")) {
                try {
                    $NewDb.Create()
                } catch {
                    $CreateDBException = @()
                    $CreateDBException += $_.Exception.Message
                    $Exception = $_.Exception

                    while ($Exception.InnerException) {
                        $CreateDBException += $Exception.InnerException.Message
                        $Exception = $Exception.InnerException
                    }

                    Stop-Function -Message "Error creating Database $Name on server $SqlInstance; Error messages: $CreateDBException" `
                        -ErrorRecord $_ -Target $instance -Continue
                }


                #now do post db creation work, set the dbowner and set the default filegroup
                #Set the owner
                Write-Message -message "Setting database owner to $Owner" -level verbose
                try {
                    $NewDB.SetOwner($Owner)
                } catch {
                    Stop-Function -Message "Error setting Database Owner to $Owner" -ErrorRecord $_ -Target $instance -Continue
                }

                #set the user filegroup to be the default
                write-message -message "Setting default filegroup to $UserFileGroupName" -level verbose
                try {
                    $NewDB.SetDefaultFileGroup($UserFileGroupName)
                } catch {
                    Stop-Function -Message "Error setting default filegorup to $UserFileGroupName" -ErrorRecord $_ -Target $instance -Continue
                }

            }

            #Write completed message
            Write-Message -message "Completed creating database $Name on server $instance" -level Output
        }

    }
}