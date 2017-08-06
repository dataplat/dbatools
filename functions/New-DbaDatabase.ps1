function New-DbaDatabase 
{
  <#
.SYNOPSIS 
New-DbaADatabase creates a new database

.DESCRIPTION
New-DbaDatabase creates a new database with a single user filegroup, and the PRIMARY filegroup reserved for system objects.
It allows creation with multiple files, and sets all growth settings to be fixed size rather than percentage growth.

.PARAMETER SqlInstance
The SQL server instances to be connected to; can be passed in via the pipeline.

.PARAMETER Force
The force parameter will ignore some errors in the parameters and assume defaults.

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES 
Original Author: Matthew Darwin (@evoDBA, naturalselectiondba.wordpress.com)
Tags: Database
	
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/New-DbaAgentJob

.EXAMPLE   
New-DbaAgentJob -SqlInstance sql1 -DatabaseName 'TestDatabase' -UserDataFileSize 128 -UserDataFileMaxSize 1024 -UserDataFileGrowth 128 `
-LogSize 128 -LogGrowth 128
Creates a database named TestDatabase on instance sql1 with a user filegroup with a single file of 128MB

#>

    [cmdletbinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    Param 
    ( 
    # set variables for the database
            [parameter(Mandatory = $true, ValueFromPipeline = $true)]
		    [Alias("ServerInstance", "SqlServer")]
		    [DbaInstanceParameter[]]$SqlInstance
          , [PSCredential]$SqlCredential  
          , [parameter(Mandatory = $true)]
            [string]$DatabaseName                      
          , [double]$NumberOfFilesInUserFilegroup = 1

    # optional db variables
          , [boolean]$UseDefaultFileLocations = $true
          , [string]$NonDefaultFileLocation
          , [string]$NonDefaultLogLocation
          , [string]$Collation
          , [string]$RecoveryModel
          , [string]$DatabaseOwner = "sa"

    #set the user data size, maxsize and growth
          , [double]$UserDataFileSize 
          , [double]$USerDataFileMaxSize
          , [double]$UserDataFileGrowth #use 0 for no growth

    #set the log size and growth
          , [double]$LogSize
          , [double]$LogGrowth

    #set the primary file size in MB (will be converted to kb later)
          , [double]$PrimaryFileSize = 10
          , [double]$PrimaryFileGrowth = 10
          , [double]$PrimaryFileMaxSize = 100
          		
    #Switches
          , [switch]$Force
		  , [switch]$Silent
    )

    begin
    {
        #Check file directories passed in if not using defaults
        if ($UseDefaultFileLocations -eq $false -and ($NonDefaultFileLocation -eq $Null -or $NonDefaultLogLocation -eq $Null))
            {
                Stop-Function -Message "Non Default file locations selected, but are not supplied" -Category InvalidData -ErrorRecord $_ -Target $instance -Continue
            }
    }


    process 
    {
        
        if (Test-FunctionInterrupt) { return }

        #Verbose message to show the server
        Write-Message -message "Connecting to server $SqlInstance" -Level Verbose

        #instantiate the sql server object
	    try {
		    $SQLServer = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
	    }
	    catch {
		    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
	    }

        #check to see if the database already exists.
        if ($SQLServer.Databases[$DatabaseName].Name -ne $Null)
        {
            Stop-Function -Message "Database $DatabaseName already exists on $TargetServer" -Target $instance -Continue
        }

        # if we are using the default file locations, get them from the server
        if ($UseDefaultFileLocations -eq $true)
        {
            #get the default file locations; if the master is in the default location we use that path as the default file will not be set
            $LocalDataDrive = if ($SQLServer.DefaultFile -eq [DBNULL]::value)
                                        {$SQLServer.MasterDBPath} 
                                    else
                                        {$SQLServer.DefaultFile}
            $LocalLogDrive = $SQLServer.DefaultLog
        }
        elseif ($UseDefaultFileLocations -eq $false)
        {
            $LocalDataDrive = $NonDefaultFileLocation
            $LocanewlLogDrive = $NonDefaultLogLocation
        }
        
        #output message in verbose mode
        Write-Message -message "Set local Data drive to $LocalDataDrive and local log drive to $LocalLogDrive" -level verbose

        #create the new db object

        try
        {
            write-message -message "Creating smo object for new database $DatabaseName" -level verbose
            $NewDB = New-Object Microsoft.SqlServer.Management.Smo.Database($SQLServer, $DatabaseName)
        }
        catch
        {
            Stop-Function -Message "Error creating database object for $DatabaseName on server $Sqlserver" -ErrorRecord $_ -Target $instane -Continue
        }

        #add the primary filegroup and a primary file
        try
        {
            write-message -message "Creating PRIMARY filegroup" -level Verbose
            $PrimaryFG = new-object Microsoft.SqlServer.Management.Smo.Filegroup($NewDB, "PRIMARY")
            $NewDB.Filegroups.Add($PrimaryFG)
        }
        catch
        {
            Stop-Function -Message "Error creating Primary filegroup object" -ErrorRecord $_ -Target $instance -Continue
        }

        #add the primary file
        try
        {
            $PrimaryFileName = $DatabaseName + "_PRIMARY"
            Write-Message -message "Creating file name $PrimaryFileName in filegroup PRIMARY" -level verbose

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
        }
        catch
        {
            Stop-Function -Message "Error adding file to Primary filegroup" -ErrorRecord $_ -Target $instance -Continue
        }

        #add the user data file group
        try
        {
            $UserFilegroupName = $DatabaseName + "_MainData"
            write-Message -message "Creating user filegroup $UserFileGroupName" -level Verbose
            
            $UserFG = new-object Microsoft.SqlServer.Management.Smo.Filegroup($NewDB, $UserFilegroupName)
            $NewDB.Filegroups.Add($UserFG)
        }
        catch
        {
            Stop-Function -Message "Error creating user filegroup" -ErrorRecord $_ -Target $instance -Continue
        }

        #add the required number of files to the filegroup in a loop
        #set the filecounter
        $FileCounter = 1

        #open a loop while the filecounter is less than the required number of files
        While ($FileCounter -le $NumberOfFilesInUserFilegroup)
        {
            #Set the file name
            try
            {
                $UserFileName = $UserFileGroupName + "_" + [string]$FileCounter
                Write-Message -message "Creating file name $UserFileName in filegroup $UserFileGroupName" -Level Verbose
                #create the smo object for the file
                $UserFile = new-object Microsoft.SQLServer.Management.Smo.Datafile($UserFG, $UserFileName)
                $UserFile.FileName = $LocalDataDrive + "\" + $USerFileName + ".ndf"
                $UserFile.Size = ($UserDataFileSize * 1024)
                $UserFile.GrowthType = "KB"
                $UserFile.Growth = ($UserDataFileGrowth * 1024)
                $UserFile.MaxSize = ($USerDataFileMaxSize * 1024)
                #add the file to the filegroup
                $UserFG.Files.Add($UserFile)
            }
            catch
            {
                Stop-Function -Message "Error adding file $FileCounter to $UserFileGroupName" -ErrorRecord $_ -Target $instance -Continue
            }
            #increment the file counter
            $FileCounter = $FileCounter + 1
        }

        #now create the log file
        try
        {
            $LogName = $DatabaseName + "_Log"
            write-message -message "Creating log $LogName" -level verbose
            #add the log to the db
            $TLog = new-object Microsoft.SqlServer.Management.Smo.LogFile($NewDB, $LogName)
            $TLog.FileName = $LocalLogDrive + "\" + $LogName + ".ldf"
            $TLog.Size = ($LogSize * 1024)
            $TLog.GrowthType = "KB"
            $TLog.Growth = ($LogGrowth * 1024)
            #add the log to the db
            $NewDB.LogFiles.Add($TLog)
        }
        catch
        {
            Stop-Function -Message "Error adding log file to database." -ErrorRecord $_ -Target $instance -Continue
        }

        #set database settings; collation, owner, recovery model

        #set the collation
        if ($Collation.Length -eq 0)
        {
            $Message = "USing default server collation"
            Write-Verbose $Message
        }
        else
        {
            $Message = "Setting collation to $Collation"
            Write-Verbose $Message
            $NewDB.Collation = $Collation
        }

        #set the recovery model
        if ($RecoveryModel.Length -eq 0)
        {
            $Message = "Using default recovery model from the Model database"
            Write-Verbose $Message
        }
        else
        {
            Write-Message -message "Setting recovery model to $RecoveryModel" -level Verbose
            $NewDB.RecoveryModel = $RecoveryModel
        }

        #we should now be able to create the db, and run any other config settings afterwards
        Write-Message -message "Creating Datbase $DatabaseName" -level verbose
        if ($PSCmdlet.ShouldProcess($instance, "Creating the database on $instance")) 
        {
            try
            {
                $NewDb.Create()
            }
            catch
            {
                Stop-Function -Message "Error creating Database $DatabaseName on server $SqlInstance" -ErrorRecord $_ -Target $instance -Continue
            }      


            #now do post db creation work, set the dbowner and set the default filegroup
            #Set the owner
            Write-Message -message "Setting database owner to $DatabaseOwner" -level verbose
            try
            {
                $NewDB.SetOwner($DatabaseOwner)
            }
            catch
            {
                Stop-Function -Message "Error setting Database Owner to $DatabaseOwner" -ErrorRecord $_ -Target $instance -Continue
            }

            #set the user filegroup to be the default
            write-message -message "Setting default filegroup to $UserFileGroupName" -level verbose
            try
            {
                $NewDB.SetDefaultFileGroup($UserFileGroupName)
            }
            catch
            {
                Stop-Function -Message "Error setting default filegorup to $UserFileGroupName" -ErrorRecord $_ -Target $instance -Continue
            }

        }

        #Write completed message
        Write-Message -message "Completed creating database $DatabaseName on server $sqlInstance" -level Verbose

    }
}