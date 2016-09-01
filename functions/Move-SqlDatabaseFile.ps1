Function Move-SqlDatabaseFile
{
<#
.SYNOPSIS
Helps moving databases files to another location with safety.
Is usefull when a new drive is delivered or when need to move files to another drive to free space.

.DESCRIPTION
This function will perform the following steps:
    1. Set database offline
    2. Copy file(s) from source to destination
    3. Alter database files location on database metadata (using ALTER DATABASE [db] MODIFY FILE command)
    4. Bring database Online
    5. Perform DBCC CHECKDB 
    6. If everything is OK remove the old files.


Copy method:
    If running localy
        - Use Robocopy. If not exits use Start-BitsTransfer

    If run remotely   
        - Check if user have access to UNC paths (\\) 
            - if yes uses robocopy
            - If not, try Remote Session (PSSession)
                uses robocopy on the machine if exists

The -Databases parameter is autopopulated for command-line completion and can be used to copy only specific objects.

.PARAMETER SqlServer
The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.


.PARAMETER ExportExistingFiles
This switch with the -OutFile parameter will generate an CSV file with all database files. 
The CSV have a column named 'Destination' which must be filled with the destination path you want.
You must remove all lines that have files you don't want to move.

.PARAMETER OutFile
This must be specified when using -ExportExistingFiles switch. 
This specifies the CSV file to write to. 
Must include the path.

.PARAMETER MoveFromCSV
This switch indicate that you will specify an CSV input file using the -InputFile parameter to say which files want to move.

.PARAMETER $InputFile,
This must be specified when using -ExportExistingFiles switch.
This specifies the CSV file to read from.
Must include the path.  

.PARAMETER CheckFileHash
This switch allows a validation using file's hashes. Generate hash for source and destination files and check if is the same.
This may take a long time for bigger files.

.PARAMETER NoDbccCheckDb
If this switch is used the DBCC CHECK DB will be skipped. USE THIS WITH CARE

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

.LINK
https://dbatools.io/Move-SqlDatabaseFile

.EXAMPLE 
Move-SqlDatabaseFile -SqlServer sqlserver2014a -Databases db1 

Will show a grid to select the file(s), then a treeview to select the destination path and perform the move (copy&paste&delete)

.EXAMPLE 
Move-SqlDatabaseFile -SqlServer sqlserver2014a -Databases db1 -ExportExistingFiles -OutFile "C:\temp\files.csv"

Will generate a files.csv files to C:\temp folder with the list of all files within database 'db1'.
This file will have an empty column called 'destination' that should be filled by user and run the command again passing this file. 

.EXAMPLE 
Move-SqlDatabaseFile -SqlServer sqlserver2014a -Databases db1 -FileType DATA

Will show a treeview to select the destination path and perform the move (copy&paste&delete) of every file of DATA (ROWS) type

#>	
	[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName="Default")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[parameter(Mandatory = $true, ParameterSetName = "ExportExistingFiles")]
		[switch]$ExportExistingFiles,
		[parameter(Mandatory = $true, ParameterSetName = "ExportExistingFiles")]
        [Alias("OutFilePath", "OutputPath")]
		[string]$OutFile,
        [parameter(Mandatory = $true, ParameterSetName = "MoveFromCSV")]
		[switch]$MoveFromCSV,
		[parameter(Mandatory = $true, ParameterSetName = "MoveFromCSV")]
        [Alias("InputFilePath", "InputPath")]
		[string]$InputFile,
        [switch]$CheckFileHash,
        [switch]$NoDbccCheckDb,
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
				$sql = "select DB_NAME (dbid) as dbname, name, filename, '' AS destination, groupid from sysaltfiles"
			}
			else
			{
				$sql = "SELECT db.name AS dbname, type_desc AS FileType, mf.name, Physical_Name AS filename, '' AS destination FROM sys.master_files mf INNER JOIN  sys.databases db ON db.database_id = mf.database_id"
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
            Write-Output "Set database '$database' Offline!"
            $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$database] SET OFFLINE WITH ROLLBACK IMMEDIATE") | Out-Null

            do
            {
                $server.Databases[$database].Refresh()
                Start-Sleep -Seconds 1
                $WaitingTime += 1
                Write-Output "Database status: $($server.Databases[$database].Status.ToString())"
                Write-Output "Waiting Time: $WaitingTime seconds"
            }
            while (($server.Databases[$database].Status.ToString().Contains("Offline") -eq $false) -and $WaitingTime -le 10)

            #Validate
            if ($server.Databases[$database].Status.ToString().Contains("Offline") -eq $false)
            {
                throw "Cannot set database '$database' in OFFLINE status."
            }
            else
            {
                Write-Output "Database set OFFLINE successfull! $($server.Databases[$database].Status.ToString())"
            }
        }

        function Set-SqlDatabaseOnline
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
                Write-Warning "DBCC skipped. -NoDbccChecDB was used."
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
                    #TODO: Ask Rob why only CheckTables (duration?)
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

            if (@("Local_Robocopy","Local_Bits") -contains $copymethod)
            {
                #Verify if file exists on both folders (source and destination)
                if ((Test-SqlPath -SqlServer $server -Path $DestinationFilePath) -and (Test-SqlPath -SqlServer $server -Path $SourceFilePath))
                {
                    try
                    {
                        #TODO: ONLY REMOVE FILES AFTER BRINGONLINE & DBCC CHECKDB??
                        #Delete old file already copied to the new path
                        Write-Output "Deleting file '$SourceFilePath'"
                                
                        Remove-Item -Path $SourceFilePath
        
                        Write-Output "File '$SourceFilePath' deleted" 
                    }
                    catch
                    {
                        Write-Exception $_
                        Write-Warning "Can't delete the file '$SourceFilePath'. Delete it manualy"
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
                                            Write-Exception $_
                                            Write-Warning "Can't delete the file '$SourceFilePath'. Delete it manualy"
                                        }
                                    }
                                    else
                                    {
                                        Write-Warning "File $SourceFilePath does not exists! No file copied!"
                                    }
                                }
                Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $SourceFilePath
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

        #Which method will be used?
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

        if ($ExportExistingFiles)
        {
            if (($OutFile.Length -gt 0)) #-and (!(Test-Path -Path $OutFile)))
            {
                $files | Export-Csv -LiteralPath $OutFile -NoTypeInformation
                Write-Output "Edit the file $OutFile. Keep only the rows matching the fies you want to move. Fill 'destination' column for each file.`r`n"
                Write-Output "Use the following command to move the files:`r`nMove-SqlDatabaseFile -SqlServer $SqlServer -Databases $database -MoveFromCSV -InputFilePath '$OutFile'"
                return
            }
            else
            {
                throw "The choosed file path does not exists"
            }
        }


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
                #Select one file to move
		        $FilesToMove = $files | Out-GridView -PassThru
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
                    $filepathToMove = Show-SqlServerFileSystem -SqlServer $server -SqlCredential $SqlCredential

                    if ($filepathToMove.length -le 0)
                    {
                        throw "No path chossen"
                        return
                    }

                    foreach ($File in $FilesToMove)
                    {
                        $File.Destination = $filepathToMove
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

        try
        {
            $testRobocopyExistance = robocopy
            $RobocopyExistsLocally = $true
            Write-Output "Robocopy exists locally."
        }
        catch
        {
            $RobocopyExistsLocally = $false
            Write-Output "Cannot find robocopy."
        }

        if ($env:computername -eq $sourcenetbios)
        {
            if ($RobocopyExistsLocally)
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
            #TODO: Find a way to validate some drive. C: exists everytime?
            #Check if have permission to UNC path (this will be checked again for each file that needs to be move)
            if (Test-Path -Path $(Join-AdminUnc -servername $sourcenetbios -FilePath "C:\") -IsValid)
            {
                if ($RobocopyExistsLocally)
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
                $copymethod = "PSSession_Remote"
            }
        }

        if (@("Local_Robocopy","Local_Bits") -contains $copymethod)
        {
            Write-Output "You are running this command locally. Using Bits to copy the files"
        
            #Import-Module BitsTransfer -Verbose
        
            $filesProgressbar = 0
        
            #Get number of files to move
            if (!([string]::IsNullOrEmpty($FilesToMove.Count)))
            {
                $FilesCount = $FilesToMove.Count
            }
            else
            {
                $FilesCount = @($FilesToMove).Count
            }
            
            #Call function to set database offline
            Set-SqlDatabaseOffline
        
            foreach ($file in $FilesToMove)
            {
                $filesProgressbar += 1
        
                $dbName = $File.dbname
                $LogicalName = $file.Name
                $DestinationPath = $file.Destination
                $SourcePath = Split-Path -Path $($file.FileName)
                $FileToCopy = Split-Path -Path $($file.FileName) -leaf
                $ValidDestinationPath = !([string]::IsNullOrEmpty($DestinationPath))
                
                Write-Progress `
							-Id 1 `
							-Activity "Working on file: $LogicalName on database: '$dbName'" `
							-PercentComplete ($filesProgressbar / $FilesCount * 100) `
							-Status "Copying - $filesProgressbar of $FilesCount files"
        
                if ($ValidDestinationPath)
                {
                    
                    if ($copymethod -eq "UNC_BITS")
                    {
                        $SourceFilePath = Join-AdminUnc -servername $sourcenetbios -FilePath $file.FileName
                        $LocalDestinationFilePath = $(Join-Path $DestinationPath $fileToCopy)
                        $DestinationFilePath = Join-AdminUnc -servername $sourcenetbios -FilePath $LocalDestinationFilePath
        
                        $LocalSourcePath = Split-Path -Path $SourceFilePath
                        $LocalDestinationPath = Split-Path -Path $DestinationFilePath
                    }
                    else
                    {
                        $SourceFilePath = $file.FileName
                        $LocalDestinationFilePath = $(Join-Path $DestinationPath $fileToCopy)
                        $DestinationFilePath = $LocalDestinationFilePath
        
                        $LocalSourcePath = Split-Path -Path $SourceFilePath
                        $LocalDestinationPath = Split-Path -Path $DestinationFilePath 
                    }
        
        
                    if ($copymethod -eq "UNC_BITS")
                    {
                        $resultPath = (Test-Path -Path $DestinationPath -IsValid)
                    }
                    else
                    {
                        $resultPath = (Test-SqlPath -SqlServer $server -Path $DestinationPath)
                    }
        
                    if (!($resultPath))
                    {
                        Write-Warning "Destination path  for logical name '$LogicalName' does not exists. '$DestinationPath'"
                        Continue
                    }
        
                }
                else
                {
                    Write-Warning "Destination path for logical name '$LogicalName' is not valid."
                    Continue
                }
        
                if (!(Test-SqlPath -SqlServer $server -Path $SourceFilePath))
                {
                    Write-Warning "Source file or path for logical name '$LogicalName' does not exists. '$SourceFilePath'"
                    Continue
                }
        
                if (($DestinationPath -eq $SourcePath) -or ([string]::IsNullOrEmpty($DestinationPath)))
                {
                    Write-Warning "Destination path for file '$LogicalName' is the same of source path or is empty. Skipping"
                    continue
                }
        
                Write-Verbose "Copy file from path: $SourcePath"
                Write-Verbose "Copy file to path: $DestinationPath"
                Write-Verbose "Copy file: $fileToCopy"
                Write-Verbose "DestinationPath and filename: $DestinationFilePath"
        
                try
                {
                    $startRC = [System.Diagnostics.Stopwatch]::StartNew()
        
                    if ($RobocopyExistsLocally)
                    {
                        # Define regular expression that will gather number of bytes copied
                        $RegexBytes = '(?<=\s+)\d+(?=\s+)';
        
                        #region Robocopy params
                        # MIR = Mirror mode
                        # NP  = Don't show progress percentage in log
                        # NC  = Don't log file classes (existing, new file, etc.)
                        # BYTES = Show file sizes in bytes
                        # NJH = Do not display robocopy job header (JH)
                        # NJS = Do not display robocopy job summary (JS)
                        # TEE = Display log in stdout AND in target log file
                        #$CommonRobocopyParams = '/MIR /NP /NDL /NC /BYTES /NJH /NJS';
                        $CommonRobocopyParams = '/ndl /TEE /bytes /nfl /L';
        
                        #endregion Robocopy params
        
                        #region Robocopy Staging
                        Write-Verbose -Message 'Analyzing robocopy job ...';
                        $StagingLogPath = '{0}\temp\{1} robocopy staging.log' -f $env:windir, (Get-Date -Format 'yyyy-MM-dd hh-mm-ss');
        
                        $StagingArgumentList = '"{0}" "{1}" "{2}" /LOG:"{3}" /L {4}' -f $LocalSourcePath, $LocalDestinationPath, $FileToCopy, $StagingLogPath, $CommonRobocopyParams;
                        Write-Verbose -Message ('Staging arguments: {0}' -f $StagingArgumentList);
                        Start-Process -Wait -FilePath robocopy.exe -ArgumentList $StagingArgumentList -NoNewWindow;
                        # Get the total number of files that will be copied
                        $StagingContent = Get-Content -Path $StagingLogPath;
                        $TotalFileCount = $StagingContent.Count - 1;
        
                        # Get the total number of bytes to be copied
                        [RegEx]::Matches(($StagingContent -join "`n"), $RegexBytes) | % { $BytesTotal = 0; } { $BytesTotal += $_.Value; };
                        Write-Verbose -Message ('Total bytes to be copied: {0}' -f $BytesTotal);
                        #endregion Robocopy Staging
        
                        #region Start Robocopy
                        # Begin the robocopy process
                        $CommonRobocopyParams = '/ndl /TEE /bytes /NC'; #/MT:2
        
        
        
                        $RobocopyLogPath = '{0}\temp\{1} robocopy.log' -f $env:windir, (Get-Date -Format 'yyyy-MM-dd hh-mm-ss');
                        $ArgumentList = '"{0}" "{1}" "{2}" /LOG:"{3}" {4}' -f $LocalSourcePath, $LocalDestinationPath, $FileToCopy, $RobocopyLogPath, $CommonRobocopyParams;
        
                        #$ArgumentList = '"{0}" "{1}" /LOG:"{2}" /ipg:{3} {4}' -f $Source, $Destination, $RobocopyLogPath, $Gap, $CommonRobocopyParams;
                        Write-Verbose -Message ('Beginning the robocopy process with arguments: {0}' -f $ArgumentList);
                        
                        $Robocopy = Start-Process -FilePath robocopy.exe -ArgumentList $ArgumentList -Verbose -PassThru -NoNewWindow;
                        Start-Sleep -Milliseconds 100;
                        #endregion Start Robocopy
        
                        ##region Progress bar loop
                        do
		                {
                            $LogContent = Get-Content -Path $RobocopyLogPath;
        
                            $Files = $LogContent -match "^\s*(\d+)\s+(\S+)"
                            #Write-Warning "Files"
                            #$Files
                            if ($Files -ne $Null )
                            {
	                            $copied = ($Files[0..($Files.Length-2)] | %{$_.Split("`t")[-2]} | Measure -sum).Sum
	                            if ($LogContent[-1] -match "(100|\d?\d\.\d)\%")
	                            {
                                    #Write-Output "-percentComplete: $($LogContent[-1].Trim("% `t"))" 
                                    #Write-Output "LogContent[-1]: $($LogContent[-1])"
		                            Write-progress Copy -PercentComplete $LogContent[-1].Trim("% `t") $LogContent[-1]
		                            $Copied += $Files[-1].Split("`t")[-2] /100 * ($LogContent[-1].Trim("% `t"))
	                            }
	                            else
	                            {
		                            Write-progress Copy -Complete
	                            }
                            }
                        }
                        while (!$Robocopy.HasExited)
                    }
                    else
                    {
                        $BITSoutput = Start-BitsTransfer -Source $SourceFilePath -Destination $DestinationFilePath -RetryInterval 60 -RetryTimeout 60 `
                                                         -DisplayName "Copying file" -Description "Copying '$FileToCopy' to '$DestinationPath' on '$sourcenetbios'" `
                                                         -TransferType Upload
                    }
        
                    $totaltimeRC= ($startRC.Elapsed)
                    Write-Output "Total Elapsed time robocopy: $totaltimeRC"
                    
                    if ($CheckFileHash)
                    {
                        if (Compare-FileHashes -SourceFilePath $SourceFilePath -DestinationFilePath $DestinationFilePath)
                        {
                            Write-Output "File copy OK! Hash is the same."
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
                        Write-Output "Check file's hashes skipped."
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
        
            #TODO: Remove Progressbar!
        }
        else #$copymethod = "PSSession_Remote"
        {
            #Se não estiver configurado pode ser corrido este comando no destino.
            #Demasiados passos?
            #Enable-PSRemoting -force
            
            Write-Output "You are running this command remotely. Will try use Remote PS with robocopy to copy the files."

            # Test for WinRM #Test-WinRM neh. 
		    winrm id -r:$sourcenetbios 2>$null | Out-Null
		    if ($LastExitCode -eq 0) 
            { 
                $remotepssession = New-PSSession -ComputerName $sourcenetbios

                if([string]::IsNullOrEmpty($remotepssession))
                {
                    $IsRemote = $false
                    Write-Warning "Connecting to remote server '$sourcenetbios' failed. We will try with Copy-Item method."
                }
                else
                {
                    $IsRemote = $true
                

                    Write-Output "LastExitCode: $LastExitCode"
                    #$remotepssession = Enter-PSSession -ComputerName $sourcenetbios

                    Write-Output "remotepssession: $($remotepssession.Id)"

                    #Enter-PSSession -Session $remotepssession

                    Write-Output "Verifying if robocopy.exe exists on default path."
                    $scriptblock = {param($SourceFilePath) Test-Path -Path "C:\Windows\System32\Robocopy.exe"}
                    $RobocopyExists = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $SourceFilePath
            
                    if ($RobocopyExists)
                    {

                        Write-Output "Using Robocopy.exe to copy the files"
                        $copymethod = "ROBOCOPY"
            
                        Get-PSSession

                        Set-SqlDatabaseOffline

                        foreach ($file in $FilesToMove)
                        {
                            
                            Connect-PSSession -Session $remotepssession
                            #$filesProgressbar += 1

                            $dbName = $File.dbname
                            $DestinationPath = $file.Destination
                            $SourceFilePath = $file.FileName
                            $LogicalName = $file.Name
                            $SourcePath = Split-Path -Path $($file.FileName)
                            $FileToCopy = Split-Path -Path $($file.FileName) -leaf

                            $ValidDestinationPath = !([string]::IsNullOrEmpty($DestinationPath))
                
                            $DestinationFilePath = $null
                            
                            if (!([string]::IsNullOrEmpty($FilesToMove.Count)))
                            {
                                $FilesCount = $FilesToMove.Count
                            }
                            else
                            {
                                $FilesCount = @($FilesToMove).Count
                            }

                            Write-Progress `
						    	        -Id 1 `
						    	        -Activity "Working on file: $LogicalName on database: '$dbName'" `
						    	        -PercentComplete ($filesProgressbar / $FilesCount * 100) `
						    	        -Status "Processing - $filesProgressbar of $FilesCount files"

                            if ($ValidDestinationPath)
                            {
                                $DestinationFilePath = $(Join-Path $DestinationPath $fileToCopy)

                                if (!(Test-SqlPath -SqlServer $server -Path $DestinationPath))
                                {
                                    Write-Warning "Destination path  for logical name '$LogicalName' does not exists. '$DestinationPath'"
                                    Continue
                                }
                            }
                            else
                            {
                                Write-Warning "Destination path for logical name '$LogicalName' is not valid."
                                Continue
                            }

                            if (!(Test-SqlPath -SqlServer $server -Path $SourceFilePath))
                            {
                                Write-Warning "Source file or path for logical name '$LogicalName' does not exists. '$SourceFilePath'"
                                Continue
                            }

                            if (($DestinationPath -eq $SourcePath) -or ([string]::IsNullOrEmpty($DestinationPath)))
                            {
                                Write-Warning "Destination path for file '$LogicalName' is the same of source path or is empty. Skipping"
                                continue
                            }
        
                            Write-Verbose "Using RemoteSession - Copy file from path: $SourcePath"
                            Write-Verbose "Using RemoteSession - Copy file to path: $DestinationPath"
                            Write-Verbose "Using RemoteSession - Copy file: $fileToCopy"
                            Write-Verbose "Using RemoteSession - DestinationPath and filename: $DestinationFilePath"


                            # Define regular expression that will gather number of bytes copied
                            $RegexBytes = '(?<=\s+)\d+(?=\s+)';

                            #region Robocopy params
                            # MIR = Mirror mode
                            # NP  = Don't show progress percentage in log
                            # NC  = Don't log file classes (existing, new file, etc.)
                            # BYTES = Show file sizes in bytes
                            # NJH = Do not display robocopy job header (JH)
                            # NJS = Do not display robocopy job summary (JS)
                            # TEE = Display log in stdout AND in target log file
                            #$CommonRobocopyParams = '/MIR /NP /NDL /NC /BYTES /NJH /NJS';
                            #$CommonRobocopyParams = '/NP /NDL /NC /BYTES /NJH /NJS /BYTES /COPYALL /Z /MT:12';
                            $CommonRobocopyParams = '/ndl /TEE /bytes /nfl /L';
                            

                            #endregion Robocopy params

                            #region Robocopy Staging
                            Write-Verbose -Message 'Analyzing robocopy job ...';
                            $StagingLogPath = '{0}\temp\{1}robocopystaging.log' -f $env:windir, (Get-Date -Format 'yyyyMMddhhmmss');

                            #$ScanArgs = $RobocopyArgs + " /Log:$ScanLog ".Split(" ")
                            #$RoboArgs = $RobocopyArgs + "/ndl /TEE /bytes /Log:$RoboLog ".Split(" ")

                            $StagingArgumentList = '"{0}" "{1}" "{2}" /LOG:"{3}" {4}' -f $SourcePath, $DestinationPath, $fileToCopy, $StagingLogPath, $CommonRobocopyParams;
                            Write-Verbose -Message ('Staging arguments: {0}' -f $StagingArgumentList);
                            $scriptblock = {param($StagingArgumentList) Start-Process -Wait -FilePath robocopy -PassThru -WindowStyle Hidden -ArgumentList $StagingArgumentList}

                            Write-Output $scriptblock 
                            $Robocopy = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $StagingArgumentList
                            Write-Output "Robocopy: $Robocopy"
                            Start-Sleep -Milliseconds 100;
                        
                            # Get the total number of files that will be copied
                            $scriptblock = {param($StagingLogPath) Get-Content $StagingLogPath}
                            $StagingContent = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $StagingLogPath 

                            #region Start Robocopy
                            # Begin the robocopy process
                            $RobocopyLogPath = '{0}\temp\{1}robocopy.log' -f $env:windir, (Get-Date -Format 'yyyyMMddhhmmss');
                            #$ArgumentList = '"{0}" "{1}" /LOG:"{2}"' -f $SourcePath, $DestinationPath, $fileToCopy, $RobocopyLogPath;
                            #Write-Verbose -Message ('Beginning the robocopy process with arguments: {0}' -f $ArgumentList);
                        
                            Write-Verbose "RobocopyLogPath: $RobocopyLogPath"

                            $CommonRobocopyParams = '/ndl /TEE /bytes /NC';


                            $ArgumentList = '"{0}" "{1}" "{2}" /LOG:"{3}" {4}' -f $SourcePath, $DestinationPath, $fileToCopy, $RobocopyLogPath, $CommonRobocopyParams;
                            Write-Verbose -Message ('Execution arguments: {0}' -f $ArgumentList);
                            $scriptblock = {param($ArgumentList) Start-Process robocopy -PassThru -WindowStyle Hidden -ArgumentList $ArgumentList}                        
                            $CopyList = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $ArgumentList

                            Start-Sleep -Milliseconds 500;
        
                            $FileSize = [regex]::Match($StagingContent[-4],".+:\s+(\d+)\s+(\d+)").Groups[2].Value
                            write-verbose ("Robocopy Bytes: $FileSize `n" +($StagingContent -join "`n"))

                            #Add progressbar http://stackoverflow.com/questions/13883404/custom-robocopy-progress-bar-in-powershell
                            Write-Output 'Waiting for file copies to complete...'		
		                    do
		                    {
                                Start-Sleep -Milliseconds 100
                                Write-Warning "While!"
                                $scriptblock = {Get-Process "robocopy*"}
                                $CopyList = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock
                                Write-Warning "End Get-Process"

                                Write-Output "CopyList"
                                $CopyList


                                Write-Output "RobocopyLogPath: $RobocopyLogPath"
                                $scriptblock = {
                                                param($RobocopyLogPath) 
                                                $file = [System.io.File]::Open($RobocopyLogPath, 'Open', 'Read', 'ReadWrite')
                                                $reader = New-Object System.IO.StreamReader($file)

                                                $text = @()
                                                while(($line = $reader.ReadLine()) -ne $null)
                                                {
                                                    $text+= "$line `t`r`n";
                                                }
                                                $reader.Close()
                                                $file.Close()
                                                return $text
                                               }
                                $LogContent = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $RobocopyLogPath

                                $Files = $LogContent -match "^\s*(\d+)\s+(\S+)"

                                if ($Files -ne $Null)
                                {
                                    if ($LogContent[-1] -match "(100|\d?\d\.\d)\%")
	                                {
                                        Write-Output "-percentComplete: $($LogContent[-1].Trim("% `t"))"
                                        Write-Output "LogContent[-1]: $($LogContent[-1])"
                                        Write-progress Copy -PercentComplete $LogContent[-1].Split("%")[0] $LogContent[-1]
	                                }
	                                else
	                                {
		                                Write-progress Copy -Complete
	                                }
                                }
		                    }
                            while (@($CopyList | Where-Object {$_.HasExited -eq $false}).Count -gt 0)

                            Set-SqlDatabaseFileLocation -Database $dbName -LogicalFileName $LogicalName -PhysicalFileLocation $DestinationFilePath
                        }
                    }
                }
            }
            else
            {
                throw "Remote PowerShell access not enabled on $sourcenetbios or access denied. Windows admin acccess required. Quitting." 
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

        foreach ($file in $FilesToMove)
        {
            $FileToCopy = Split-Path -Path $($file.FileName) -leaf
            $SourceFilePath = $file.FileName
            $DestinationFilePath = $(Join-Path $DestinationPath $fileToCopy)

            Remove-OldFile -SourceFilePath $SourceFilePath -DestinationFilePath $DestinationFilePath
        }

        #If remote session. Clear
        if ($copymethod -eq "PSSession_Remote")
        {
            Write-Verbose "Exiting-PSSession"
            Disconnect-PSSession $remotepssession.Id

            Write-Verbose "Removing PSSession with id $($remotepssession.Id)"
            Remove-PSSession $remotepssession.Id
        }
	}
	
	# END is to disconnect from servers and finish up the script. When using the pipeline, things in here will be executed last and only once.
	END
	{
		$server.ConnectionContext.Disconnect()

        $totaltime = ($start.Elapsed)
        Write-Output "Total Elapsed time: $totaltime"

        #Remove-PSSession $remotepssession.Id
		If ($Pscmdlet.ShouldProcess("console", "Showing final message"))
		{
			
			
		}
	
	}
}