Function Move-SqlDatabaseFile
{
<#
.SYNOPSIS
Helps moving databases files to another location with safety.
Is usefull when a new drive/lun is delivered or when we need to move files to another drive/lun to free space.

.DESCRIPTION
This function will perform the following steps:
    1. Set database offline
    2. Copy file(s) from source to destination
    3. Alter database files location on database metadata (using ALTER DATABASE [db] MODIFY FILE command)
    4. Bring database Online
    5. Perform DBCC CHECKDB - You can skip this step if you want to execute it manually after check that database is online.

By default the source files would not be deleted. But if you want, you can use -DeleteSourceFiles switch.


Copy method:
    If running localy
        - Use Robocopy. If not exits use Start-BitsTransfer

    If run remotely   
        - Check if user have access to UNC paths (\\) 
            - if yes uses robocopy
            - If not, try Remote Session (PSSession) -> if not enabled on target machine you can enable by using the following command: Enable-PSRemoting -force
                uses robocopy on the machine if exists

The -Databases parameter is autopopulated for command-line completion and can be used to copy only specific objects.

.PARAMETER SqlServer
The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER Databases
Will appear once you chose a -SqlServer that you have access.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER ExportDatabaseStructure
This switch with the -OutFile parameter will generate an CSV file with all database files. 
The CSV have a column named 'DestinationFolderPath' which must be filled with the destination path you want.
You must remove all lines that have files you don't want to move.

.PARAMETER OutFile
This must be specified when using -ExportDatabaseStructure switch. 
This specifies the CSV file to write to. 
Must include the path.

.PARAMETER MoveFromCSV
This switch indicate that you will specify an CSV input file using the -InputFile parameter to say which files want to move.

.PARAMETER InputFile,
This must be specified when using -ExportDatabaseStructure switch.
This specifies the CSV file to read from.
Must include the path.  

.PARAMETER CheckFileHash
This switch allows a validation using file's hashes. Generate hash for source and destination files and check if is the same.
This may take a long time for bigger files.

.PARAMETER NoDbccCheckDb
If this switch is used the DBCC CHECK DB will be skipped. USE THIS WITH CARE!
You may want to use this switch if your database is big. But you should execute the command after.

.PARAMETER DeleteSourceFiles
If this switch is used the source files will be deleted after database comes online with success.

.PARAMETER Force
This switch will continue to perform rest of the actions even if DBCC produces an error.

.NOTES 
Original Author: Cláudio Silva (@ClaudioESSilva)

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

References:
    Copy-WithProgress using robocopy -> http://stackoverflow.com/questions/13883404/custom-robocopy-progress-bar-in-powershell
    Thanks to Trevor Sullivan's    
    A excellent example behind most of this robocopy code.

.LINK
https://dbatools.io/Move-SqlDatabaseFile

.EXAMPLE 
Move-SqlDatabaseFile -SqlServer sqlserver2014a -Databases db1 

Will show a grid to select the file(s), then a treeview to select the destination path and perform the file copy

.EXAMPLE 
Move-SqlDatabaseFile -SqlServer sqlserver2014a -Databases db1 -ExportDatabaseStructure -OutFile "C:\temp\files.csv"

Will generate a files.csv files to C:\temp folder with the list of all files within database 'db1'.
This file will have an empty column called 'DestinationFolderPath' that should be filled by user and run the command again passing this file. 

.EXAMPLE 
Move-SqlDatabaseFile -SqlServer sqlserver2014a -Databases db1 -FileType DATA

Will show a treeview to select the destination path and perform the file copy of every file of DATA (ROWS) type

.EXAMPLE
Move-SqlDatabaseFile -SqlServer sqlserver2014a -Databases db1 -DeleteSourceFiles

Will show a grid to select the file(s), then a treeview to select the destination path and perform the move (copy&paste&delete) every selected file

.EXAMPLE
Move-SqlDatabaseFile -SqlServer sqlserver2014a -Databases db1 -NoDbccCheckDb

Will show a grid to select the file(s), then a treeview to select the destination path and perform the copy every selected file. 
Will NOT perform a DBCC CHECKDB!
Usefull if you want to run it manually (for example, because database is big and will take too much time)

.EXAMPLE
Move-SqlDatabaseFile -SqlServer sqlserver2014a -Databases db1 -CheckFileHash

Will show a grid to select the file(s), then a treeview to select the destination path and perform the copy every selected file. 
Will perform a file hash validation for each file after his copy.
Will perform a DBCC CHECKDB!
Usefull if you want to run it manually (for example, because database is big and will take too much time)

#>	
	[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName="Default")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[parameter(Mandatory = $true, ParameterSetName = "ExportDatabaseStructure")]
		[switch]$ExportDatabaseStructure,
		[parameter(Mandatory = $true, ParameterSetName = "ExportDatabaseStructure")]
        [Alias("OutFilePath", "OutputPath")]
		[string]$OutFile,
        [parameter(Mandatory = $true, ParameterSetName = "MoveFromCSV")]
		[switch]$MoveFromCSV,
		[parameter(Mandatory = $true, ParameterSetName = "MoveFromCSV")]
        [Alias("InputFilePath", "InputPath")]
		[string]$InputFile,
        [switch]$CheckFileHash,
        [switch]$NoDbccCheckDb,
        [switch]$DeleteSourceFiles,
        [switch]$Force
	)
	
	DynamicParam 
    { 
        if ($sqlserver)
		{
			$dbparams = Get-ParamSqlDatabases -SqlServer $SqlServer -SqlCredential $SqlCredential
			$allparams = Get-ParamSqlDatabaseFileTypes -SqlServer $SqlServer -SqlCredential $SqlCredential
			$null = $allparams.Add("Databases", $dbparams.Databases)
			return $allparams
		}
    }
	
	BEGIN
	{
		
		function Get-SqlFileStructure
		{
			if ($server.versionMajor -eq 8)
			{
				$sql = "select DB_NAME (dbid) as dbname, name, filename, CAST(mf.Size * 8 AS DECIMAL(20,2)) AS sizeKB, '' AS Drive, '' AS DestinationFolderPath, groupid from sysaltfiles"
			}
			else
			{
				$sql = "SELECT db.name AS dbname, type_desc AS FileType, mf.name, Physical_Name AS filename, CAST(mf.Size * 8 AS DECIMAL(20,2)) AS sizeKB, '' AS Drive, '' AS DestinationFolderPath FROM sys.master_files mf INNER JOIN  sys.databases db ON db.database_id = mf.database_id"
			}
			
			$dbfiletable = $server.ConnectionContext.ExecuteWithResults($sql)
			$ftfiletable = $dbfiletable.Tables[0].Clone()
			$dbfiletable.Tables[0].TableName = "data"
			
			foreach ($db in $databaselist)
			{
				# Add support for Full Text Catalogs in Sql Server 2005 and below
				if ($server.VersionMajor -lt 10)
				{
					#$dbname = $db.name
					$fttable = $null = $server.Databases[$database].ExecuteWithResults('sp_help_fulltext_catalogs')
					
					foreach ($ftc in $fttable.Tables[0].rows)
					{
						$name = $ftc.name
						$physical = $ftc.Path
						$logical = "sysft_$name"
						$null = $ftfiletable.Rows.add($database, "FULLTEXT", $logical, $physical)
					}
				}
			}
			
			$null = $dbfiletable.Tables.Add($ftfiletable)
			return $dbfiletable
		}

        function Set-SqlDatabaseOffline
        {
            if ($PSCmdlet.ShouldProcess($database, "Set database offline"))
            {
                Write-Output "Set database '$database' Offline!"

                $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$database] SET OFFLINE WITH ROLLBACK IMMEDIATE") | Out-Null

                do
                {
                    $server.Databases[$database].Refresh()
                    Start-Sleep -Seconds 1
                    $WaitingTime += 1
                    Write-Verbose "Database status: $($server.Databases[$database].Status.ToString())"
                    Write-Verbose "Waiting for database become offline: $WaitingTime seconds passed"
                }
                while (($server.Databases[$database].Status.ToString().Contains("Offline") -eq $false) -and $WaitingTime -le 10)

                #Validate
                if ($server.Databases[$database].Status.ToString().Contains("Offline") -eq $false)
                {
                    throw "Cannot set database '$database' in OFFLINE status."
                }
                else
                {
                    Write-Output "Database set OFFLINE successfull! Actual state: '$($server.Databases[$database].Status.ToString())'"
                }
            }
        }

        function Set-SqlDatabaseOnline
        {
            if ($PSCmdlet.ShouldProcess($database, "Set database online"))
            {
                Write-Output "Set database '$database' Online!"
                try
                {
                
                        $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$database] SET ONLINE") | Out-Null

                }
                catch
                {
                    Write-Warning $_
                    return $false
                }

                $WaitingTime = 0
                do
                {
                    $server.Databases[$database].Refresh()
                    Start-Sleep -Seconds 1
                    $WaitingTime += 1
                    Write-Output "Database status: $($server.Databases[$database].Status.ToString())"
                    Write-Output "WaitingTime: $WaitingTime"
                }
                while (($server.Databases[$database].Status.ToString().Contains("Normal") -eq $false) -and $WaitingTime -le 10)
            }
            if ($server.Databases[$database].Status.ToString().Contains("Normal") -eq $false)
            {
                throw "Database is not in Online status."
            }
            else
            {
                $server.Databases[$database].Status.ToString()
            }
            Write-Output "Database '$database' in Online!"

            if ($NoDbccCheckDb -eq $false)
            {
                Write-Output "Starting Dbcc CHECKDB for $dbname on $source"
			    $dbccgood = Start-DbccCheck -Server $server -DBName $dbname
					
			    if ($dbccgood -eq $false)
			    {
				    if ($force -eq $false)
				    {
					    Write-Output "DBCC failed for $dbname (you should check that).  Aborting routine for this database"
					    continue
				    }
				    else
				    {
					    Write-Output "DBCC failed, but Force specified. Continuing."
				    }
			    }
            }
            else
            {
                Write-Warning "DBCC skipped. -NoDbccChecDB switch was used."
            }

            return $true
            
        }

        function Set-SqlDatabaseFileLocation
        {
            Param 
            (
                [parameter(Mandatory = $true)]
		        [string]$Database,
                [parameter(Mandatory = $true)]
		        [string]$LogicalFileName,
                [parameter(Mandatory = $true)]
		        [string]$PhysicalFileLocation
            )
            if ($PSCmdlet.ShouldProcess($database, "Modifying file '$LogicalFileName' location to '$PhysicalFileLocation'"))
            {
                Write-Output "Modifying file path to new location"
                try
                {
                    $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$database] MODIFY FILE (NAME = $LogicalFileName, FILENAME = '$PhysicalFileLocation');") | Out-Null
                }
                catch
                {
                    Write-Exception $_
                }
            }      
        }

        function Compare-FileHashes
        {
            <#
                .SYNOPSIS
                Get file's hashes and compare them
                Return boolean value
            #>
            Param
            (
                [parameter(Mandatory = $true)]
		        [string]$SourceFilePath,
                [parameter(Mandatory = $true)]
		        [string]$DestinationFilePath
            )
            
            Write-Output "Comparing file hash".
            
            $SourceHash = Get-FileHash -FilePath $SourceFilePath
            $DestinationHash = Get-FileHash -FilePath $DestinationFilePath

            Write-Verbose "SourceHash     : $SourceHash"
            Write-Verbose "DestinationHash: $DestinationHash"

            $SameHash = $SourceHash -eq $DestinationHash
            Write-Verbose "Source file hash is equal?: $SameHash"

            return $SameHash
        }

        function Get-FileHash
        {
            <#
                .SYNOPSIS
                Generate a file hash
                
                .NOTES
                This can take some time on larger files.
            #>
            Param
            (
                [parameter(Mandatory = $true)]
		        [string]$FilePath
            )

            if ($PSCmdlet.ShouldProcess($sourcenetbios, "Generating hash for file '$FilePath'"))
            {
                Write-Output "Generating hash for file: '$FilePath'"
                $stream = New-Object io.FileStream ($FilePath, 'open')
                $Provider = New-Object System.Security.Cryptography.MD5CryptoServiceProvider 
                $Hash = New-Object System.Text.StringBuilder 
                if ($stream) 
                { 
                    foreach ($byte in $Provider.ComputeHash($stream)) 
                    {
                        [Void] $Hash.Append($byte.ToString("X2"))
                    } 
                    $stream.Close() 
                }

                return $Hash
            }

        }

        #Maybe turn this into sharedfunction
        Function Start-DbccCheck
		{
			param (
				[object]$server,
				[string]$dbname
			)
			
			$servername = $server.name
			$db = $server.databases[$dbname]
			
			if ($Pscmdlet.ShouldProcess($sourceserver, "Running dbcc check on $dbname on $servername"))
			{
				try
				{
					$null = $db.CheckTables('None')
					Write-Output "Dbcc CHECKDB finished successfully for $dbname on $servername"
				}
				
				catch
				{
					Write-Warning "DBCC CHECKDB failed"
					Write-Exception $_
					
					if ($force)
					{
						return $true
					}
					else
					{
						return $false
					}
				}
			}
		}

        Function Remove-OldFile
        {
            <#
                .SYNOPSIS
                Remove source file

                .DESCRIPTION
                To run after database come online with success!
                Verify if both files exists. Then remove the old file.
            #>
            Param (
				[string]$SourceFilePath,
				[string]$DestinationFilePath
			)

            if (@("Local_Robocopy","Local_Bits", "UNC_Robocopy", "UNC_Bits") -contains $copymethod)
            {
                #Verify if file exists on both folders (source and destination)
                if ((Test-SqlPath -SqlServer $server -Path $DestinationFilePath) -and (Test-SqlPath -SqlServer $server -Path $SourceFilePath))
                {
                    try
                    {
                        #TODO: ONLY REMOVE FILES AFTER BRINGONLINE & DBCC CHECKDB??
                        #Delete old file already copied to the new path
                        Write-Output "Deleting file '$SourceFilePath'"
                        
                        if ($PSCmdlet.ShouldProcess($sourcenetbios, "Deleting file '$SourceFilePath'"))
                        {     
                            Remove-Item -Path $SourceFilePath
                        }
        
                        Write-Output "File '$SourceFilePath' deleted" 
                    }
                    catch
                    {
                        Write-Warning "Can't delete the file '$SourceFilePath'. Delete it manualy"
                        continue
                    }
                }
                else
                {
                    Write-Warning "File $SourceFilePath does not exists! No file copied!"
                }
            }
            else #remotely
            {
                #Delete old file already copied to the new path
                Write-Output "Deleting file '$SourceFilePath' remotely"
                $scriptblock = {
                                    param($SourceFilePath) 
                                
                                    #Verify if file exists on both folders (source and destination)
                                    if ((Test-Path -Path $DestinationFilePath) -and (Test-Path -Path $SourceFilePath))
                                    {
                                        try
                                        {
                                            #Delete old file already copied to the new path
                                            Write-Output "Deleting file '$SourceFilePath'"
                                            
                                            Remove-Item -Path $SourceFilePath 

                                            Write-Output "File '$SourceFilePath' deleted" 
                                        }
                                        catch
                                        {
                                            Write-Warning "Can't delete the file '$SourceFilePath'. Delete it manualy."
                                            continue
                                        }
                                    }
                                    else
                                    {
                                        Write-Warning "File $SourceFilePath does not exists! No file copied!"
                                    }
                                }
                if ($PSCmdlet.ShouldProcess($sourcenetbios, "Deleting file '$SourceFilePath'"))
                { 
                    Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $SourceFilePath
                }
            }
        }

        Function Test-PathsAccess
        {
            <#
                .SYNOPSIS
                Will test if we have access to the specified paths.

                .DESCRIPTION
                Will create a file and delete it.
                If can't delete will warn about it.
            #>
            Param (
				    [object]$PathsToUse
			      )
            
            $ArrayList = @()
            [System.Collections.ArrayList]$PathsAlreadyTested = $ArrayList

            foreach ($Path in $PathsToUse)
            {
                try
                {
                    $ValidPath = !([string]::IsNullOrEmpty($($Path.DestinationFolderPath)))
                    $DestinationFolderPath = $Path.DestinationFolderPath

                    if ($ValidPath)
                    {
                        if ($DestinationFolderPath -eq $Path.SourceFoldePath)
                        {
                            Write-Warning "Destination path for file '$LogicalName' is the same of source path. Skipping"
                            continue
                        }

                        $dummyFilePath = "$DestinationFolderPath\DBATools_dummy$(Get-Date -Format 'yyyyMMddhhmmss').log"

                        if ($PathsAlreadyTested.Contains($DestinationFolderPath))
                        {
                            continue
                        }

                        if ($copymethod -ne "PSSession_Remote")
                        {
                            if ($PSCmdlet.ShouldProcess($sourcenetbios, "Test file creation on '$dummyFilePath'"))
                            {
                                $null = New-Item -ItemType File -Path $dummyFilePath
                            }
                        
                            Write-Verbose "Can access on destination path '$dummyFilePath'."
                            try
                            {
                                if ($PSCmdlet.ShouldProcess($sourcenetbios, "Deleting file '$dummyFilePath'"))
                                {
                                    Remove-Item -Path $dummyFilePath
                                }
                            }
                            catch
                            {
                                Write-Warning "Can't delete dummy file '$dummyFilePath'. Please delete it manually."
                            }
                        }
                        else
                        {
                            $scriptblock = {
                                                param($FilePath) 
                                
                                                New-Item -ItemType File -Path $FilePath
                        
                                                Write-Output "Can access on destination path."
                                                try
                                                {
                                                    Remove-Item -Path $FilePath
                                                }
                                                catch
                                                {
                                                    Write-Warning "Can't delete dummy file '$FilePath'. Please delete it manually."
                                                }
                                            }
                            if ($PSCmdlet.ShouldProcess($sourcenetbios, "Test file creation on '$dummyFilePath'"))
                            {
                                Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $dummyFilePath
                            }
                            
                        }

                        $null = $PathsAlreadyTested.Add($DestinationFolderPath)
                    }
                    else
                    {
                        Write-Warning "The specified path '$DestinationPathToUse' is not valid."
                        Write-Exception $_
                    }
                }
                catch
                {
                    Write-Error $_
                    Write-Warning "Can't create files on path '$DestinationPathToUse'"
                    continue
                }
            }
        }

        Function Disconnect-RemovePSSession
        {
            if ($PSCmdlet.ShouldProcess($sourcenetbios, "Disconnect and removing PSSession '$($remotepssession.Id)'"))
            {
                Write-Verbose "Disconnect-PSSession"
                Disconnect-PSSession $remotepssession.Id

                Write-Verbose "Removing PSSession with id $($remotepssession.Id)"
                Remove-PSSession $remotepssession.Id
            }
        }

        Function Check-SpaceRequirements
        {
            #Verify file size and check if destination drive have sufficient freespace
            try
            {
                if ($PSCmdlet.ShouldProcess($sourcenetbios, "Getting drives free space using Get-DbaDiskSpace command"))
                {
                    Write-Output "Getting drives free space using Get-DbaDiskSpace command."
                    [object]$AllDrivesFreeDiskSpace = Get-DbaDiskSpace -ComputerName $sourcenetbios -Unit KB | Select-Object Name, FreeInKB

                    #1st Get all drives/luns from files to move
                    foreach ($DBFile in $FilesToMove)
                    {
                        #Verfiy path using Split-Path on $logfile.FileName in backwards. This way we will catch the LUNs. Example: "K:\Log01" as LUN name
                        $DrivePath = Split-Path $DBFile.FileName -parent
                        Do  
                        {
                            if ($AllDrivesFreeDiskSpace | Where-Object {$DrivePath -eq "$($_.Name)"})
                            {
                                #$TotalTLogFreeDiskSpaceKB = ($AllDrivesFreeDiskSpace | Where-Object {$DrivePath -eq $_.Name}).SizeInKB
                                $DBFile.Drive = $DrivePath
                                $match = $true
                                break
                            }
                            else
                            {
                                $match = $false
                                $DrivePath = Split-Path $DrivePath -parent
                            }

                        }
                        while (!$match -or ([string]::IsNullOrEmpty($DrivePath)))
                    }

                    #2nd Group size by drive/lun
                    $TotalSpaceNeeded = $FilesToMove `
                                        | Group-Object Drive `
                                        | Select-Object Name, `
                                                        @{Name=‘TotalSpaceNeeded’;Expression={($_.Group | Measure-Object sizeKB -Sum).Sum}}

                    #3rd compare with $InstanceSpace luns free space
                    foreach ($Drive in $TotalSpaceNeeded)
                    {
                        [long]$FreeDiskSpace = ($AllDrivesFreeDiskSpace | Where-Object {$Drive.Name -eq $_.Name}).FreeInKB.ToString().Replace(".", "")
                        $FreeDiskSpaceMB = [math]::Round($($FreeDiskSpace / 1024), 2)
                        $TotalSpaceNeededMB = [math]::Round($($Drive.TotalSpaceNeeded / 1024), 2)

                        if ($Drive.TotalSpaceNeeded -le $FreeDiskSpace)
                        {
                            Write-Output "Drive '$($Drive.Name)' has sufficient free space ($FreeDiskSpaceMB MB) for all files to be copied (Space needed: $($Drive.TotalSpaceNeeded / 1024) MB)'"
                        }
                        else
                        {
                            throw "Drive '$($Drive.Name)' does not have sufficient space available. Needed: '$TotalSpaceNeededMB MB'. Existing: $FreeDiskSpaceMB MB. Quitting"
                        }
                    }

                    Write-Output "Space requirements checked!"
                }
            }
            catch
            {
                Write-Exception $_
            }
        }

        Function Get-PSSessionRobocopyLogContent
        {
            $scriptblock = {
                                param($RobocopyLogPath) 
                                $file = [System.io.File]::Open($RobocopyLogPath, 'Open', 'Read', 'ReadWrite')
                                $reader = New-Object System.IO.StreamReader($file)

                                #done this way to replicate Get-Content output (is a collection :))
                                $text = @()
                                while(($line = $reader.ReadLine()) -ne $null)
                                {
                                    $text+= "$line"
                                }
                                $reader.Close()
                                $file.Close()
                                return $text
                            }
            
            if ($PSCmdlet.ShouldProcess($sourcenetbios, "Reading robocopy log content using PSSession id '$($remotepssession.Id)'"))
            {
                $PSSessionRoboCopyLogContent = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $RobocopyLogPath

                return $PSSessionRoboCopyLogContent
            }
        }
		
		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential

		$source = $server.DomainInstanceName
		
		$Databases = $psboundparameters.Databases
		$FileType = $psboundparameters.FileType

        if ($Filetype -eq 'DATA') { $Filetype = 'ROWS' }
	}
	
	PROCESS
	{
		Write-Output "Get database file inventory"
		$filestructure = Get-SqlFileStructure

        Write-Output "Resolving NetBIOS name"
        $sourcenetbios = Resolve-NetBiosName $server
        Write-Output "SourceNetBios: $sourcenetbios"
	
		foreach ($database in $Databases)
		{
            if ($server.Databases["$database"])
	        {
			    $where = "dbname = '$database'"
			
			    if ($FileType.Length -gt 0)
			    {

				    $where = "$where and filetype = '$filetype'"
			    }
			
			    $files = $filestructure.Tables.Select($where)
            }
            else
            {
                Write-Warning "Database '$database' does not exists on server $($Server.name)"
            }
		}

        if ($ExportDatabaseStructure)
        {
            if (($OutFile.Length -gt 0)) #-and (!(Test-Path -Path $OutFile)))
            {
                $files | Export-Csv -LiteralPath $OutFile -NoTypeInformation
                Write-Output "Edit the file $OutFile. Keep only the rows matching the fies you want to move. Fill 'DestinationFolderPath' column for each file (path only).`r`n"
                Write-Output "Use the following command to move the files:`r`nMove-SqlDatabaseFile -SqlServer $SqlServer -Databases $database -MoveFromCSV -InputFilePath '$OutFile'"
                return
            }
            else
            {
                throw "The choosed file path does not exists"
            }
        }


        $FilesToMove = @()

        if ($MoveFromCSV)
        {
            if (($InputFile.Length -gt 0) -and (Test-Path -Path $InputFile))
            {
                $FilesToMove = Import-Csv -LiteralPath $InputFile
            }
            else
            {
                throw "The choosed file path does not exists"
            }
        }
        else
        {
            if (([string]::IsNullOrEmpty($FileType)))
            {
		        $FilesToMove = $files | Out-GridView -PassThru -Title "Select one or more files to move:"
            }
            else
            {
                Write-Output "Will move all files of type '$FileType'"
                $FilesToMove = $files
            }

            if (@($FilesToMove).Count -gt 0)		
            {
		        # This will go above
		        if ($filepath.length -eq 0)
		        {
			        #Open dialog box with GUI
                    $filepathToMove = Show-SqlServerFileSystem -SqlServer $server -SqlCredential $SqlCredential -Whatif:$false

                    if ($filepathToMove.length -le 0)
                    {
                        throw "No path was chosen."
                        return
                    }

                    foreach ($File in $FilesToMove)
                    {
                        $File.DestinationFolderPath = $filepathToMove
                    }
		        }
		        else
		        {
                    #Need to move to PS-Session block
			        $exists = Test-SqlPath -SqlServer $server -Path $FilePath
			        if ($exists -eq $false)
			        {
				        throw "Directory does not exist"
			        }
		        }
            }
            else
            {
                throw "No files were selected!"
            }
            
        }
        
        <#
            Validate type of copy
            Can be (using this order):
             - Local copy:
                Use Robocopy. If not exits use Start-BitsTransfer
             
             - Remote copy 
                If user have access to UNC paths (\\) uses robocopy
             
                If not, use Remote Session (uses robocopy on the machine if exists)
        #>

        $start = [System.Diagnostics.Stopwatch]::StartNew()

        #test if robocopy exists locally 
        try
        {
            $testRobocopyExistance = robocopy
            $RobocopyExists = $true
            $copymethod = "Local_Robocopy"
            Write-Output "Robocopy exists locally."
        }
        catch
        {
            Write-Exception $_
            $RobocopyExists = $false
            $copymethod = "Local_Bits"
            Write-Output "Cannot find robocopy."
        }

        if ($env:computername -eq $sourcenetbios)
        {
            if ($RobocopyExists)
            {
                $copymethod = "Local_Robocopy"
            }
            else
            {
                $copymethod = "Local_Bits"
            }
        }
        else
        {
           #Check if have permission to UNC path (this will be checked again for each file that needs to be move)
           if (Test-Path -Path $(Join-AdminUnc -servername $sourcenetbios -FilePath $(@($FilesToMove).Item(0).DestinationFolderPath)) -IsValid)
           {
               if ($RobocopyExists)
               {
                   $copymethod = "UNC_Robocopy"
               }
               else
               {
                   $copymethod = "UNC_Bits"
               }
           }
           else
           {
                # Test for WinRM #Test-WinRM neh. 
                if ($PSCmdlet.ShouldProcess($sourcenetbios, "Testing remotee connection to '$sourcenetbios'"))
                {
                    winrm id -r:$sourcenetbios 2>$null | Out-Null
                    if ($LastExitCode -eq 0) 
                    { 
                        $remotepssession = New-PSSession -ComputerName $sourcenetbios

                        if([string]::IsNullOrEmpty($remotepssession))
                        {
                            throw "Can't create remote PowerShell session on $sourcenetbios. Quitting."
                        }
                        else
                        {
                            Write-Output "LastExitCode: $LastExitCode"
                            Write-Verbose "Created remote pssession id: $($remotepssession.Id)"
 
                            Write-Output "Verifying if robocopy.exe exists on default path."
                      
                            $RemoteRobocopyExists = Invoke-Command -Session $remotepssession -ScriptBlock {robocopy} -ErrorAction SilentlyContinue

                            if ($RemoteRobocopyExists)
                            {
                                $copymethod = "PSSession_Remote"
                                #Write-Output "Using Robocopy to copy the files"
                            }
                            else
                            {
                                #Disconnect and remove PSSession
                                Disconnect-RemovePSSession
                                throw "Robocopy does not exists on remote machine '$sourcenetbios'. Quitting."
                            }

                        }
                    }
                    else
                    {
                        throw "Remote PowerShell access not enabled on $sourcenetbios or access denied. Windows admin acccess required. Quitting." 
                    }
                }
                else
                {
                    $copymethod = "PSSession_Remote"
                }
            }
        }

        #Add support columns to collection
        $FilesToMove | Add-Member -NotePropertyName FileToCopy -NotePropertyValue ""
        $FilesToMove | Add-Member -NotePropertyName SourceFilePath -NotePropertyValue ""
        $FilesToMove | Add-Member -NotePropertyName SourceFolderPath -NotePropertyValue ""
        $FilesToMove | Add-Member -NotePropertyName DestinationFilePath -NotePropertyValue ""
        #DestinationFolderPath already exists
        
        #To use when changing file location metadata
        $FilesToMove | Add-Member -NotePropertyName LocalDestinationFilePath -NotePropertyValue ""
        $FilesToMove | Add-Member -NotePropertyName LocalDestinationFolderPath -NotePropertyValue ""

        #Says if file is already handled with success. Used to print files to delete
        $FilesToMove | Add-Member -NotePropertyName SuccefullHandled -NotePropertyValue $false

        #Format files accordingly with copy type
        foreach ($file in $FilesToMove)
        {
            $fileToCopy = Split-Path -Path $($file.FileName) -leaf

            $file.FileToCopy = $fileToCopy
           
            Write-Host "DestinationFolderPath: $($file.DestinationFolderPath)"
            Write-Host "DestinationFolderPath: $fileToCopy"

            $file.LocalDestinationFilePath = [System.IO.Path]::Combine($file.DestinationFolderPath,$fileToCopy)

            #$file.LocalDestinationFilePath = Join-Path $file.DestinationFolderPath $fileToCopy -
            $file.LocalDestinationFolderPath = $file.DestinationFolderPath

            if (@("UNC_Robocopy", "UNC_Bits") -contains $copymethod)
            {
                $file.SourceFilePath = Join-AdminUnc -servername $sourcenetbios -FilePath $($file.FileName)

                $ManageUNCPath = Join-AdminUnc -servername $sourcenetbios -FilePath $(Split-Path -Path $($file.FileName))

                if($ManageUNCPath.EndsWith("$\"))
                {
                    $ManageUNCPath = $ManageUNCPath.TrimEnd("\")
                }
                                
                $file.SourceFolderPath = $ManageUNCPath


                $FileDestinationFolderPathFilename = [System.IO.Path]::Combine($file.DestinationFolderPath,$fileToCopy)
                $file.DestinationFilePath = Join-AdminUnc -servername $sourcenetbios -FilePath $FileDestinationFolderPathFilename
                #$file.DestinationFilePath = Join-AdminUnc -servername $sourcenetbios -FilePath $(Join-Path $file.DestinationFolderPath $fileToCopy)
                
                $ManageUNCPath = Join-AdminUnc -servername $sourcenetbios -FilePath $file.DestinationFolderPath

                if($ManageUNCPath.EndsWith("$\"))
                {
                    $ManageUNCPath = $ManageUNCPath.TrimEnd("\")
                }
                                
                $file.DestinationFolderPath = $ManageUNCPath
                #TODO

            }
            else
            {
                $file.SourceFilePath = $file.FileName
                $file.SourceFolderPath = $(Split-Path -Path $($file.FileName))

                $file.DestinationFilePath = Join-Path $file.DestinationFolderPath $fileToCopy
            }
        }

        Test-PathsAccess -PathsToUse $FilesToMove

        Check-SpaceRequirements

        #Get number of files to move
        $FilesCount = @($FilesToMove).Count

        #TODO: REMOVE
        #$copymethod = "Local_Bits1"
        #$RobocopyExists = $false

        if (@("Local_Robocopy","Local_Bits", "UNC_Robocopy", "UNC_Bits") -contains $copymethod)
        {
            Write-Output "You are running this command locally."

            switch ($copymethod)
			{
				"Local_Robocopy" {
					Write-Output "We will use robocopy as copy method."
                    break
				}

                "Local_Bits" {
					Write-Output "We will use BitsTransfer as copy method."
                    break
				}

                "UNC_Robocopy" {
					Write-Output "We will use robocopy with UNC paths as copy method."
                    break
				}

                "UNC_Bits" {
					Write-Output "We will use BitsTransfer with UNC paths as copy method."
                    break
				}

            }

            $filesProgressbar = 0

            #Call function to set database offline
            Set-SqlDatabaseOffline
        
            foreach ($file in $FilesToMove)
            {
                $filesProgressbar += 1

                #$file.FileToCopy
                #$file.SourceFilePath
                #$file.SourceFolderPath
                #$file.DestinationFilePath
                #$file.DestinationFolderPath
                #$file.LocalDestinationFilePath
                #$file.LocalDestinationFolderPath
        
                $dbName = $file.dbname
                $LogicalName = $file.Name
                $FileToCopy = $file.FileToCopy

                $LocalFilePath = $file.filename
                
                $SourceFilePath = $file.SourceFilePath
                $SourceFolderPath = $file.SourceFolderPath

                $DestinationFilePath = $file.DestinationFilePath
                $DestinationFolderPath = $file.DestinationFolderPath

                $LocalDestinationFilePath = $file.LocalDestinationFilePath
                $LocalDestinationPath = $file.LocalDestinationFolderPath
                
                Write-Progress `
							-Id 1 `
							-Activity "Copying file: '$FileToCopy' on database: '$dbName'" `
							-PercentComplete ($filesProgressbar / $FilesCount * 100) `
							-Status "Copying - $filesProgressbar of $FilesCount files"
        
                if (!(Test-SqlPath -SqlServer $server -Path $LocalFilePath))#$SourceFilePath))
                {
                    Write-Warning "Source file or path for logical name '$LogicalName' does not exists. '$LocalFilePath'"
                    Continue
                }
        
                if (($LocalDestinationPath -eq $SourceFolderPath) -or ([string]::IsNullOrEmpty($LocalDestinationPath)))
                {
                    Write-Warning "Destination path for file '$LogicalName' is the same of source path or is empty. Skipping"
                    continue
                }
        
                Write-Verbose "Copy file from path: $SourceFolderPath"
                Write-Verbose "Copy file to path: $DestinationFolderPath"
                Write-Verbose "Copy file: $fileToCopy"
                Write-Verbose "DestinationPath and filename: $DestinationFilePath"
        
                try
                {
                    $startRC = [System.Diagnostics.Stopwatch]::StartNew()
        
                    if ($RobocopyExists)
                    {
                        # MIR = Mirror mode
                        # NP  = Don't show progress percentage in log
                        # NC  = Don't log file classes (existing, new file, etc.)
                        # BYTES = Show file sizes in bytes
                        # NJH = Do not display robocopy job header (JH)
                        # NJS = Do not display robocopy job summary (JS)
                        # TEE = Display log in stdout AND in target log file
                        $CommonRobocopyParams = '/ndl /TEE /bytes /NC /COPY:DATS /R:10 /W:3'; #/MT:2

                        $RobocopyLogPath = "$env:windir\temp\$((Get-Date -Format 'yyyyMMddhhmmss'))Robocopy.log"
                        #format this way because the double-quotes ""
                        $ArgumentList = '"{0}" "{1}" "{2}" /LOG:"{3}" {4}' -f $SourceFolderPath, $DestinationFolderPath, $FileToCopy, $RobocopyLogPath, $CommonRobocopyParams;
                        Write-Verbose "Beginning the robocopy process with arguments: $ArgumentList"

                        if ($PSCmdlet.ShouldProcess($sourcenetbios, "Executing robocopy to copy file: '$FileToCopy' from '$SourceFolderPath' to '$DestinationFolderPath'"))
                        {
                            $Robocopy = Start-Process -FilePath robocopy.exe -ArgumentList $ArgumentList -Verbose -PassThru -NoNewWindow

                            Start-Sleep -Milliseconds 100;

                            Write-Output 'Waiting for file copies to complete...'	
                            do
		                    {
                                $LogContent = Get-Content -Path $RobocopyLogPath;

                                $RobocopyLogFiltered = $LogContent -match "^\s*(\d+)\s+(\S+)"

                                if ($RobocopyLogFiltered -ne $Null )
                                {
	                                if ($LogContent[-1] -match "(100|\d?\d\.\d)\%")
	                                {
		                                Write-progress -Id 2 -ParentId 1 -Activity "Progress" -PercentComplete $LogContent[-1].Split("%")[0] $LogContent[-1]
	                                }
	                                else
	                                {
                                        if ($LogContent[-1].StartsWith("Waiting"))
                                        {
                                            Write-Warning "$($LogContent[-3]) - $($LogContent[-1])"
                                            Start-Sleep -Milliseconds 3000;
                                        }
                                        else
                                        {
		                                    Write-progress -Id 2 -ParentId 1 -Activity "Progress" -Complete
                                        }
	                                }
                                }
                                Start-Sleep -Milliseconds 250;
                            }
                            while (!$Robocopy.HasExited)

                            #Get content one last time to verify if it finished by "RETRY LIMIT EXCEEDED"
                            $LogContent = Get-Content -Path $RobocopyLogPath;
                            if ($LogContent | Where-Object { $_ -match "ERROR: RETRY LIMIT EXCEEDED." })
                            {
                                $file.SuccefullHandled = $false
                                Write-Warning "Can not copy file '$FileToCopy'. Please confirm that you have permissions to paths '$SourceFolderPath' and '$DestinationFolderPath'"
                                continue
                            }
                            else
                            {
                                $file.SuccefullHandled = $true
                            }

                            Write-progress -Id 2 -ParentId 1 "Progress" -Complete
                        }
                    }
                    else
                    {
                        try
                        {
                            if ($PSCmdlet.ShouldProcess($sourcenetbios, "Executing Start-BitsTransfer to transfer file '$FileToCopy' from '$SourceFolderPath' to '$DestinationFolderPath'"))
                            {
                                $BITSoutput = Start-BitsTransfer -Source $SourceFilePath -Destination $LocalDestinationFilePath -RetryInterval 60 -RetryTimeout 60 `
                                                                 -DisplayName "Copying file" -Description "Copying '$FileToCopy' to '$DestinationFolderPath' on '$sourcenetbios'" 
                            }
                            $file.SuccefullHandled = $true
                        }
                        catch
                        {
                            Write-Error $_
                            $file.SuccefullHandled = $false
                        }
                    }
        
                    $totaltimeRC= ($startRC.Elapsed)
                    Write-Output "Total elapsed time for copying '$FileToCopy' with robocopy: $totaltimeRC"
                    
                    if ($CheckFileHash)
                    {
                        if (Compare-FileHashes -SourceFilePath $SourceFilePath -DestinationFilePath $DestinationFilePath)
                        {
                            Write-Output "File copy OK! Hash is the same for both files."
                        }
                        else
                        {
                            Write-Verbose "File copy NOK! Hash is not the same."
                            Write-Verbose "Deleting destination file '$DestinationFilePath'!"
                            Remove-Item -Path $DestinationFilePath
                            Write-Output "File '$DestinationFilePath' deleted" 
                        }
                    }
                    else
                    {
                        Write-Warning "The switch -CheckFileHash was not specified."
                    }

                    Write-Verbose "Change file path for logical file '$LogicalName' to '$DestinationFilePath'"
                    Set-SqlDatabaseFileLocation -Database $dbName -LogicalFileName $LogicalName -PhysicalFileLocation $LocalDestinationFilePath
                    Write-Verbose "File path changed"
                }
                catch
                {
                    Write-Exception $_
                }
            }
        
            Write-Progress `
							-Id 1 `
                            -Activity "Files copied!"`
                            -Complete
        }
        else #$copymethod = "PSSession_Remote"
        {
            Write-Output "You are running this command remotely. Will try use Remote PS Session with robocopy to copy the files."

            Set-SqlDatabaseOffline

            foreach ($file in $FilesToMove)
            {
                if ($PSCmdlet.ShouldProcess($sourcenetbios, "Connecting using Connect-PSSession"))
                {
                    Connect-PSSession -Session $remotepssession
                }
                
                $filesProgressbar += 1

                $dbName = $file.dbname
                $LogicalName = $file.Name
                $FileToCopy = $file.FileToCopy
                
                $SourceFilePath = $file.SourceFilePath
                $SourceFolderPath = $file.SourceFolderPath

                $DestinationFilePath = $file.DestinationFilePath
                $DestinationFolderPath = $file.DestinationFolderPath

                $LocalDestinationFilePath = $file.LocalDestinationFilePath
                $LocalDestinationPath = $file.LocalDestinationFolderPath

                Write-Progress `
						    -Id 1 `
						    -Activity "Working on file: $LogicalName on database: '$dbName'" `
						    -PercentComplete ($filesProgressbar / $FilesCount * 100) `
						    -Status "Processing - $filesProgressbar of $FilesCount files"


                if (!(Test-SqlPath -SqlServer $server -Path $SourceFilePath))
                {
                    Write-Warning "Source file or path for logical name '$LogicalName' does not exists. '$SourceFilePath'"
                    Continue
                }

                if (($LocalDestinationPath -eq $SourceFolderPath) -or ([string]::IsNullOrEmpty($LocalDestinationPath)))
                {
                    Write-Warning "Destination path for file '$LogicalName' is the same of source path or is empty. Skipping"
                    continue
                }
        
                Write-Verbose "Using RemoteSession - Copy file from path: $SourceFolderPath"
                Write-Verbose "Using RemoteSession - Copy file to path: $DestinationPath"
                Write-Verbose "Using RemoteSession - Copy file: $fileToCopy"
                Write-Verbose "Using RemoteSession - DestinationPath and filename: $DestinationFilePath"

                # MIR = Mirror mode
                # NP  = Don't show progress percentage in log
                # NC  = Don't log file classes (existing, new file, etc.)
                # BYTES = Show file sizes in bytes
                # NJH = Do not display robocopy job header (JH)
                # NJS = Do not display robocopy job summary (JS)
                # TEE = Display log in stdout AND in target log file
                $CommonRobocopyParams = '/ndl /TEE /bytes /nfl /COPY:DATS /L /R:10 /W:3'
                
                $RobocopyLogPath = "$env:windir\temp\$((Get-Date -Format 'yyyyMMddhhmmss'))Robocopy.log"
                Write-Verbose "RobocopyLogPath: $RobocopyLogPath"

                $CommonRobocopyParams = '/ndl /TEE /bytes /NC'

                $ArgumentList = '"{0}" "{1}" "{2}" /LOG:"{3}" {4}' -f $SourceFolderPath, $LocalDestinationPath, $fileToCopy, $RobocopyLogPath, $CommonRobocopyParams
                Write-Verbose "Execution arguments: $ArgumentList"


                if ($PSCmdlet.ShouldProcess($sourcenetbios, "Executing robocopy to copy file: '$fileToCopy'"))
                {
                    $scriptblock = {param($ArgumentList) Start-Process robocopy -PassThru -WindowStyle Hidden -ArgumentList $ArgumentList}                        
                    $CopyList = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $ArgumentList

                    Start-Sleep -Milliseconds 500

                    Write-Output 'Waiting for file copies to complete...'		
		            do
		            {
                        Start-Sleep -Milliseconds 100
                        $scriptblock = {Get-Process "robocopy*"}
                        $CopyList = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock

                        $LogContent = Get-PSSessionRobocopyLogContent

                        $RobocopyLogFiltered = $LogContent -match "^\s*(\d+)\s+(\S+)"

                        if ($RobocopyLogFiltered -ne $Null )
                        {
	                        if ($LogContent[-1] -match "(100|\d?\d\.\d)\%")
	                        {
		                        Write-progress -Id 2 -ParentId 1 -Activity "Progress" -PercentComplete $LogContent[-1].Split("%")[0] $LogContent[-1]
	                        }
	                        else
	                        {
                                if ($LogContent[-1].StartsWith("Waiting"))
                                {
                                    Write-Warning "$($LogContent[-3]) - $($LogContent[-1])"
                                    Start-Sleep -Milliseconds 3000;
                                }
                                else
                                {
		                            Write-progress -Id 2 -ParentId 1 -Activity "Progress" -Complete
                                }
	                        }
                        }
                        Start-Sleep -Milliseconds 250
		            }
                    while (@($CopyList | Where-Object {$_.HasExited -eq $false}).Count -gt 0)

                    #Get content one last time to verify if it finished by "RETRY LIMIT EXCEEDED"
                    $LogContent = Get-PSSessionRobocopyLogContent

                    if ($LogContent | Where-Object { $_ -match "ERROR: RETRY LIMIT EXCEEDED." })
                    {
                        $file.SuccefullHandled = $false
                        Write-Warning "Can not copy file '$FileToCopy'. Please confirm that you have permissions to paths '$SourceFolderPath' and '$DestinationFolderPath'"
                        continue
                    }
                    else
                    {
                        $file.SuccefullHandled = $true
                    }

                    Write-progress -Id 2 -ParentId 1 "Progress" -Complete
                }

                Write-Verbose "Change file path for logical file '$LogicalName' to '$DestinationFilePath'"
                Set-SqlDatabaseFileLocation -Database $dbName -LogicalFileName $LogicalName -PhysicalFileLocation $LocalDestinationFilePath
                Write-Verbose "File path changed"
            }
        }

        Write-Verbose "Copy done! Lets bring database Online!"
        $resultDBOnline = Set-SqlDatabaseOnline
        
        if ($resultDBOnline)
        {
            Write-Verbose "Database online!"
        }
        else
        {
            Write-Verbose "Some error happened! Check logs."
            throw "Some error happened! Check logs."
        }

        if ($DeleteSourceFiles)
        {
            Write-Output "The switch -DeleteSourceFiles was specified. Deleting source files."

            foreach ($file in $FilesToMove)
            {
                Remove-OldFile -SourceFilePath $($file.SourceFilePath) -DestinationFilePath $($file.LocalDestinationFilePath)
            }
        }
        else
        {
            if ($FilesToMove | Where-Object { $_.SuccefullHandled -eq $true})
            {
                Write-Warning "The -DeleteSourceFiles switch was not specified.`r`nSource files were not deleted! You need to manualy deleted all files copied.`r`nAfter you check that everything is OK, you can run the following command(s)."
                foreach ($file in $FilesToMove | Where-Object { $_.SuccefullHandled -eq $true})
                {
                    Write-Output "`r`nRemove-Item -Path ""$($file.SourceFilePath)"""
                }
            }
        }
	}
	
	# END is to disconnect from servers and finish up the script. When using the pipeline, things in here will be executed last and only once.
	END
	{
		$server.ConnectionContext.Disconnect()

        $totaltime = ($start.Elapsed)
        Write-Output "Total Elapsed time: $totaltime"

        #If remote session. Clear
        if ($copymethod -eq "PSSession_Remote")
        {
            #Disconnect and remove PSSession
            Disconnect-RemovePSSession
        }
	}
}