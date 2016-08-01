Function Move-SqlDatabaseFile
{
<#
.SYNOPSIS
Is usefull when a new drive is delivered or when need to move files to another drive to free space.

.DESCRIPTION
This function will perform the following steps:
    1. Set database offline
    2. Copy file(s) from source to destination
    3. Alter database files location on database metadata (using ALTER DATABASE [db] MODIFY FILE command)
    4. Bring databases Online
    5. If database is Online remove the old file.
	
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
Move-SqlDatabaseFile -Source sqlserver2014a -Databases db1 

Will show a grid to select the file(s), then a treeview to select the destination path and perform the move (copy&paste&delete)
	
#>	
	[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName="Default")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
		[parameter(Mandatory = $true, ParameterSetName= "FileTypes")]
		[string]$FilePath,
		[parameter(Mandatory = $true, ParameterSetName = "LogicalNames")]
		[hashtable]$TheHashforLogicalNamesNoIdeaWhatItcanbecalled,
		[parameter(Mandatory = $true, ParameterSetName = "Hashes")]
		[hashtable]$TheHashforTypesToDestinationNoIdeaWhatItcanbecalled
	)
	
	DynamicParam 
    { 
        if ($SqlServer) 
        {
            #$dbparams = Get-ParamSqlDatabases -SqlServer $SqlServer -SqlCredential $SourceSqlCredential 
			##$allparams = Get-ParamSqlDatabaseFiles -SqlServer $sqlserver -SqlCredential $SqlCredential
			#$null = $allparams.Add("Databases", $dbparams.Databases)
			#return $allparams
 
            return Get-ParamSqlDatabases -SqlServer $SqlServer -SqlCredential $SourceSqlCredential 
        } 
    }
	
	BEGIN
	{
		
		function Get-SqlFileStructure
		{
			if ($server.versionMajor -eq 8)
			{
				$sql = "select DB_NAME (dbid) as dbname, name, filename, groupid from sysaltfiles"
			}
			else
			{
				$sql = "SELECT db.name AS dbname, type_desc AS FileType, mf.name, Physical_Name AS filename FROM sys.master_files mf INNER JOIN  sys.databases db ON db.database_id = mf.database_id"
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
		
		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential

		$source = $server.DomainInstanceName
		
		$Databases = $psboundparameters.Databases
	}
	
	PROCESS
	{
		Write-Output "Get database file inventory"
		$filestructure = Get-SqlFileStructure
		
		# This will be used in Invoke-Command
		Write-Output "Resolving NetBIOS name"
		$sourcenetbios = Resolve-NetBiosName $server

        Write-Output "SourceNetBios: $sourcenetbios"
	
		foreach ($database in $Databases)
		{
			#$dbname = $database.name
			Write-Warning $database
			
			$where = "dbname = '$database'"
			
			if ($FileType.Length -gt 0)
			{

				$where = "$where and filetype = '$filetype'"
			}
			
			$files = $filestructure.Tables.Select($where)
		}
		
        #Select one file to move
		$SelectedFile = $files | Out-GridView -PassThru
		
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
		}
		else
		{
			$exists = Test-SqlPath -SqlServer $server -Path $FilePath
			if ($exists -eq $false)
			{
				throw "Directory does not exist"
			}
		}
		
        $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$database] SET OFFLINE WITH ROLLBACK IMMEDIATE")

        #Validate 
        if ($server.Databases[$database].Status.ToString().Contains("Offline") -eq $false)
        {
            throw "Database is not in OFFLINE status."
        }
        else
        {
            Write-Output "Database set OFFLINE succefull! $($server.Databases[$database].Status.ToString())"
        }

        $DestinationPath = $filepathToMove
        
        $SourceFilePath = $($SelectedFile.FileName)
        $SourcePath = Split-Path -Path $($SelectedFile.FileName)
        $fileToCopy = Split-Path -Path $($SelectedFile.FileName) -leaf

        $CompleteFilePath = $(Join-Path $DestinationPath $fileToCopy)

        Write-Output "Copy file from path: $SourcePath"
        Write-Output "Copy file to path: $DestinationPath"
        Write-Output "Copy file: $fileToCopy"
        Write-Output "DestinationPath and filename: $CompleteFilePath"


        #Import-Module BitsTransfer -Verbose

        #Se não estiver configurado pode ser corrido este comando no destino.
        #Demasiados passos?
        #Enable-PSRemoting -force

        Write-Output "Server to winrm: $sourcenetbios"
        
        # Test for WinRM #Test-WinRM neh. 
		winrm id -r:$sourcenetbios 2>$null | Out-Null
		if ($LastExitCode -ne 0) { throw "Remote PowerShell access not enabled on on $source or access denied. Quitting." }

        $remotepssession = New-PSSession -ComputerName $sourcenetbios

        #$remotepssession = Enter-PSSession -ComputerName $sourcenetbios

        Write-Output $remotepssession.Id

        Enter-PSSession -Session $remotepssession

        #Get-PSSession

        Write-Output $fileToMove
        
        $scriptblock = {param($SourcePath, $DestinationPath, $fileToCopy) Start-Process robocopy.exe -ArgumentList "`"$SourcePath`" `"$DestinationPath`" `"$fileToCopy`" /COPYALL /Z /MT:12" -PassThru}

        #http://infoworks.tv/bits-transfer-is-not-allowed-in-remote-powershell/
        $CopyList = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $SourcePath, $DestinationPath, $fileToCopy

        Write-Warning "Antes"
        $CopyList
        Write-Warning "Depois"
        $CopyList | Select-Object *

        #Add progressbar http://stackoverflow.com/questions/13883404/custom-robocopy-progress-bar-in-powershell
        Write-Output 'Waiting for file copies to complete...'		
		do
		{
            Write-Warning "While!"
            $CopyList = $scriptblock = {Get-Process "robocopy*"}
            Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock
            Write-Warning "End Get-Process"
			
            Start-Sleep -Seconds 3
		}
        while (@($CopyList | Where-Object {$_.HasExited -eq $false}).Count -gt 0)

        #$output = Start-BitsTransfer -Source $fileToMove -Destination $filepathToMove

        #Get-BitsTransfer



        #Em caso de erro remover o job da queue
        #Remove-BitsTransfer


        $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$database] MODIFY FILE (NAME = $($SelectedFile.Name), FILENAME = '$CompleteFilePath');") | Out-Null
       
        $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$database] SET ONLINE") | Out-Null

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


        #Delete old file already copied to the new path
        Write-Output "Deleting file '$SourceFilePath'"
        $scriptblock = {param($SourceFilePath) Remove-Item -Path $SourceFilePath}
        Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $SourceFilePath

        #Verify if file was deleted
        $scriptblock = {param($SourceFilePath) Test-Path -Path $SourceFilePath}
        $FileExists = Invoke-Command -Session $remotepssession -ScriptBlock $scriptblock -ArgumentList $SourceFilePath
        if ($FileExists)
        {
            Write-Warning "Can't delete the file '$SourceFilePath'. Delete it manualy"
        }
        else
        {
            Write-Output "File '$SourceFilePath' deleted"    
        }

        Write-Verbose "Exiting-PSSession"
        Exit-PSSession

        Write-Verbose "Removing PSSession with id $($remotepssession.Id)"
        Remove-PSSession $remotepssession.Id
		
	}
	
	# END is to disconnect from servers and finish up the script. When using the pipeline, things in here will be executed last and only once.
	END
	{
		$server.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing final message"))
		{
			
			
		}
	
	}
}
