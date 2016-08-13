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
    4. Bring databases Online
    5. If database is Online remove the old file.

If running on local, will use BitsTransfer (can't use remotely).
When running remotely try to use robocopy (not all SO have it??)
If not exists robocopy will use Copy-Item
	
The -Databases parameter is autopopulated for command-line completion and can be used to copy only specific objects.

.PARAMETER SqlServer
The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Force
If policies exists on destination server, it will be dropped and recreated.

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
Move-SqlDatabaseFile -SqlServer sqlserver2014a -Databases db1 -ExportExistingFiles -OutputFilePath "C:\temp\files.csv"

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
        [Alias("OutFile", "OutputPath")]
		[string]$OutputFilePath,
        [parameter(Mandatory = $true, ParameterSetName = "MoveFromCSV")]
		[switch]$MoveFromCSV,
		[parameter(Mandatory = $true, ParameterSetName = "MoveFromCSV")]
        [Alias("InputFile", "InputPath")]
		[string]$InputFilePath
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

            #Validate 
            if ($server.Databases[$database].Status.ToString().Contains("Offline") -eq $false)
            {
                throw "Database is not in OFFLINE status."
            }
            else
            {
                Write-Output "Database set OFFLINE succefull! $($server.Databases[$database].Status.ToString())"
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
            $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$database] MODIFY FILE (NAME = $LogicalFileName, FILENAME = '$PhysicalFileLocation');") | Out-Null
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
			$where = "dbname = '$database'"
			
			if ($FileType.Length -gt 0)
			{

				$where = "$where and filetype = '$filetype'"
			}
			
			$files = $filestructure.Tables.Select($where)
		}

        if ($ExportExistingFiles)
        {
            if (($OutputFilePath.Length -gt 0)) #-and (!(Test-Path -Path $OutputFilePath)))
            {
                $files | Export-Csv -LiteralPath $OutputFilePath -NoTypeInformation
                Write-Output "Edit the file $OutputFilePath. Keep only the rows matching the fies you want to move. Fill 'destination' column for each file.`r`n"
                Write-Output "Use the following command to move the files:`r`nMove-SqlDatabaseFile -SqlServer $SqlServer -Databases $database -MoveFromCSV -InputFilePath '$OutputFilePath'"
                return
            }
            else
            {
                throw "The choosed file path does not exists"
            }
        }


        if ($MoveFromCSV)
        {
            if (($InputFilePath.Length -gt 0) -and (Test-Path -Path $InputFilePath))
            {
                $FilesToMove = Import-Csv -LiteralPath $InputFilePath
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
            Can be:
             - Local with bits
             - Remote with PSSession $ Robocopy
             - Remote with Copy-Item (using UNC)
        #>
        if ($env:computername -eq $sourcenetbios)
        {

            Write-Output "You are running this command localy. Using Bits to copy the files"
            $copymethod = "BITS"
        
            #Import-Module BitsTransfer -Verbose

            $filesProgressbar = 0

            Set-SqlDatabaseOffline

            foreach ($file in $FilesToMove)
            {
                $filesProgressbar += 1

                $dbName = $File.dbname
                $DestinationPath = $file.Destination
                $SourceFilePath = $file.FileName
                $LogicalName = $file.Name
                $SourcePath = Split-Path -Path $($file.FileName)
                $FileToCopy = Split-Path -Path $($file.FileName) -leaf
                $ValidDestinationPath = !([string]::IsNullOrEmpty($DestinationPath))
                
                Write-Progress `
							-Id 1 `
							-Activity "Working on file: $LogicalName on database: '$dbName'" `
							-PercentComplete ($filesProgressbar / $FilesToMove.Count * 100) `
							-Status "Copying - $filesProgressbar of $($FilesToMove.Count) files"

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

                Write-Verbose "Copy file from path: $SourcePath"
                Write-Verbose "Copy file to path: $DestinationPath"
                Write-Verbose "Copy file: $fileToCopy"
                Write-Verbose "DestinationPath and filename: $DestinationFilePath"

                try
                {
                    $BITSoutput = Start-BitsTransfer -Source $SourceFilePath -Destination $DestinationFilePath -RetryInterval 60 -RetryTimeout 60 `
                                                    -DisplayName "Copying file" -Description "Copying '$FileToCopy' to $DestinationPath"

                    Set-SqlDatabaseFileLocation -Database $dbName -LogicalFileName $LogicalName -PhysicalFileLocation $DestinationFilePath


                    #Verify if file exists on both folders (source and destination)
                    if ((Test-SqlPath -SqlServer $server -Path $DestinationFilePath) -and (Test-SqlPath -SqlServer $server -Path $SourceFilePath))
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
                catch
                {
                    Write-Exception $_
                }
            }

            Write-Progress `
							-Id 1 `
                            -Activity "Files copied!"`
                            -Completed

            Set-SqlDatabaseOnline
            #TODO: Remove Progressbar!
        }
        else
        {
            #Reset variable
            $IsRemote = $false

            #Se não estiver configurado pode ser corrido este comando no destino.
            #Demasiados passos?
            #Enable-PSRemoting -force

            Write-Output "You are running this command remotely. Will try use Remote PS with robocopy to copy the files"

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

                    Enter-PSSession -Session $remotepssession

                    Write-Output "Verifying if robocopy.exe exists on default path."
                    $scriptblock = {param($SourceFilePath) Test-Path -Path "C:\Windows\System32\Robocopy.exe"}
                    $RobocopyExists = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $SourceFilePath
            
                    if ($RobocopyExists)
                    {

                        Write-Output "Using Robocopy.exe to copy the files"
                        $copymethod = "ROBOCOPY"
            
                        #Get-PSSession

                        Set-SqlDatabaseOffline

                        foreach ($file in $FilesToMove)
                        {
                            #$filesProgressbar += 1

                            $dbName = $File.dbname
                            $DestinationPath = $file.Destination
                            $SourceFilePath = $file.FileName
                            $LogicalName = $file.Name
                            $SourcePath = Split-Path -Path $($file.FileName)
                            $FileToCopy = Split-Path -Path $($file.FileName) -leaf

                            $ValidDestinationPath = !([string]::IsNullOrEmpty($DestinationPath))
                
                            Write-Verbose "Using RemoteSession - Copy file from path: $SourcePath"
                            Write-Verbose "Using RemoteSession - Copy file to path: $DestinationPath"
                            Write-Verbose "Using RemoteSession - Copy file: $fileToCopy"
                            Write-Verbose "Using RemoteSession - DestinationPath and filename: $DestinationFilePath"
                            #Write-Progress `
						    #	        -Id 1 `
						    #	        -Activity "Working on file: $LogicalName on database: '$dbName'" `
						    #	        -PercentComplete ($filesProgressbar / $FilesToMove.Count * 100) `
						    #	        -Status "Processing - $filesProgressbar of $($FilesToMove.Count) files"

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
                            $Robocopy = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $StagingArgumentList

                            Start-Sleep -Milliseconds 100;
                        
                            # Get the total number of files that will be copied
                            $scriptblock = {param($StagingLogPath) Get-Content $StagingLogPath}
                            $StagingContent = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $StagingLogPath

                            #region Start Robocopy
                            # Begin the robocopy process
                            $RobocopyLogPath = '{0}\temp\{1}robocopy.log' -f $env:windir, (Get-Date -Format 'yyyyMMddhhmmss');
                            #$ArgumentList = '"{0}" "{1}" /LOG:"{2}"' -f $SourcePath, $DestinationPath, $fileToCopy, $RobocopyLogPath;
                            #Write-Verbose -Message ('Beginning the robocopy process with arguments: {0}' -f $ArgumentList);
                        
                            $CommonRobocopyParams = '/ndl /TEE /bytes /NC';


                            $ArgumentList = '"{0}" "{1}" "{2}" /LOG:"{3}" {4}' -f $SourcePath, $DestinationPath, $fileToCopy, $RobocopyLogPath, $CommonRobocopyParams;
                            Write-Verbose -Message ('Execution arguments: {0}' -f $ArgumentList);
                            $scriptblock = {param($ArgumentList) Start-Process robocopy -PassThru -WindowStyle Hidden -ArgumentList $ArgumentList}                        
                            $CopyList = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $ArgumentList

                            Start-Sleep -Milliseconds 500;

                            #$scriptblock = {param($SourcePath, $DestinationPath, $fileToCopy) Start-Process robocopy.exe -ArgumentList "`"$SourcePath`" `"$DestinationPath`" `"$fileToCopy`" /COPYALL /Z /MT:12" -PassThru}

                            #http://infoworks.tv/bits-transfer-is-not-allowed-in-remote-powershell/
                            #$CopyList = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $SourcePath, $DestinationPath, $fileToCopy
        
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

                                $BytesCopied = 0;
                            
                                $scriptblock = {param($RobocopyLogPath) Get-Content $RobocopyLogPath}
                                $LogContent = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $RobocopyLogPath
                                Write-Warning "Log Content"
                                $LogContent
                                $Files = $LogContent -match "^\s*(\d+)\s+(\S+)"
                                Write-Warning "Files"
                                $Files
                                if ($Files -ne $Null )
                                {
	                                $copied = ($Files[0..($Files.Length-2)] | %{$_.Split("`t")[-2]} | Measure -sum).Sum
	                                if ($LogContent[-1] -match "(100|\d?\d\.\d)\%")
	                                {
		                                write-progress Copy -percentComplete $LogContent[-1].Trim("% `t") $LogContent[-1]
		                                $Copied += $Files[-1].Split("`t")[-2] /100 * ($LogContent[-1].Trim("% `t"))
	                                }
	                                else
	                                {
		                                write-progress Copy -Complete
	                                }
                                    $PercentComplete = [math]::min(100,(100*$Copied/[math]::max($Copied,$FileSize)))
	                                write-progress ROBOCOPY -PercentComplete $PercentComplete $Files[-1].Split("`t")[-1]
                                }
		                    }
                            while (@($CopyList | Where-Object {$_.HasExited -eq $false}).Count -gt 0)

                            Set-SqlDatabaseFileLocation -Database $dbName -LogicalFileName $LogicalName -PhysicalFileLocation $DestinationFilePath

                            #Delete old file already copied to the new path
                            Write-Output "Deleting file '$SourceFilePath'"
                            $scriptblock = {param($SourceFilePath) Remove-Item $SourceFilePath}
                            Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $SourceFilePath

                            #Verify if file exists on both folders (source and destination)
                            if ((Test-SqlPath -SqlServer $server -Path $DestinationFilePath) -and (Test-SqlPath -SqlServer $server -Path $SourceFilePath))
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

                            Set-SqlDatabaseOnline
                        }
                        else
                        {
                            Write-Warning "No files selected to move!"
                        }

                        Write-Verbose "Exiting-PSSession"
                        Exit-PSSession

                        Write-Verbose "Removing PSSession with id $($remotepssession.Id)"
                        Remove-PSSession $remotepssession.Id
                    }
                }
            }

            if (!($IsRemote))
            {
                Write-Output "Remote PowerShell access not enabled on '$source' or access denied. Will try using Copy-Item method" 
                $copymethod = "COPYITEM"
                
                Set-SqlDatabaseOffline
                
                $filesProgressbar = 0

                foreach ($file in $FilesToMove)
                {
                    $filesProgressbar += 1

                    $dbName = $File.dbname
                    $DestinationPath = $file.Destination
                    $SourceFilePath = $file.FileName
                    $UNCSourceFilePath = Join-AdminUnc -servername $sourcenetbios -FilePath $file.FileName
                    $LogicalName = $file.Name
                    $SourcePath = Split-Path -Path $($file.FileName)
                    $FileToCopy = Split-Path -Path $($file.FileName) -leaf
                    $ValidDestinationPath = !([string]::IsNullOrEmpty($DestinationPath))

                    Write-Progress `
							-Id 1 `
							-Activity "Working on file: $LogicalName on database: '$dbName'" `
							-PercentComplete ($filesProgressbar / $FilesToMove.Count * 100) `
							-Status "Copying - $filesProgressbar of $($FilesToMove.Count) files"

                    if ($ValidDestinationPath)
                    {
                        $DestinationFilePath = $(Join-Path $DestinationPath $fileToCopy)

                        $UNCDestinationFilePath = Join-AdminUnc -servername $sourcenetbios -FilePath $DestinationFilePath

                        #Validate access using UNC
                        if (!(Test-Path $DestinationPath -IsValid))
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
           
                    Write-Verbose "Copy-Item - Copy file to path: $DestinationPath"
                    Write-Verbose "Copy-Item - Copy file: $fileToCopy"
                    Write-Verbose "Copy-Item - Source Path and filename: $UNCSourceFilePath"
                    Write-Verbose "Copy-Item - Destination Path and filename: $UNCDestinationFilePath"

                    #Copy using UNC paths
                    try
                    {
                        Copy-Item -LiteralPath $UNCSourceFilePath -Destination $UNCDestinationFilePath
                        Write-Output "File copied to $UNCDestinationFilePath"

                        Set-SqlDatabaseFileLocation -Database $dbName -LogicalFileName $LogicalName -PhysicalFileLocation $DestinationFilePath

                        #Verify if file exists on both folders (source and destination)
                        if ((Test-Path -Path $UNCSourceFilePath) -and (Test-Path -Path $UNCSourceFilePath))
                        {
                            try
                            {
                                #Delete old file already copied to the new path
                                Write-Output "Deleting file '$UNCSourceFilePath'"
                                
                                Remove-Item -Path $UNCSourceFilePath

                                Write-Output "File '$UNCSourceFilePath' deleted" 
                            }
                            catch
                            {
                                Write-Exception $_
                                Write-Warning "Can't delete the file '$UNCSourceFilePath'. Delete it manualy"
                            }
                        }
                        else
                        {
                            Write-Warning "File $UNCSourceFilePath does not exists! No file copied!"
                        }
                    }
                    catch
                    {
                        Write-Exception $_
                    }
                }

                Write-Progress `
							-Id 1 `
                            -Activity "Files copied!"`
                            -Completed

                Set-SqlDatabaseOnline
            }
        }  
		
	}
	
	# END is to disconnect from servers and finish up the script. When using the pipeline, things in here will be executed last and only once.
	END
	{
		$server.ConnectionContext.Disconnect()

        #Remove-PSSession $remotepssession.Id
		If ($Pscmdlet.ShouldProcess("console", "Showing final message"))
		{
			
			
		}
	
	}
}