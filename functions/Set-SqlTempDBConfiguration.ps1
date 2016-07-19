function Set-SqlTempDBConfiguration{
<#
.SYNOPSIS
Sets tempdb data and log files according to best practices.

.DESCRIPTION
Function to calculate tempdb size and file configurations based on passed parameters, calculated values, and Microsoft
best practices. User must declare SQL Server to be configured and total data file size as mandatory values. Function will
then calculate number of data files based on logical cores on the target host and create evenly sized data files based
on the total data size declared by the user, with a log file 25% of the total data file size. Other parameters can adjust 
the settings as the user desires (such as different file paths, number of data files, and log file size). The function will
not perform any functions that would shrink or delete data files. If a user desires this, they will need to reduce tempdb
so that it is "smaller" than what the function will size it to before runnint the function.

.NOTES 
Original Author: Michael Fal (@Mike_Fal), http://mikefal.net

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

.PARAMETER SqlServer
SQLServer name or SMO object representing the SQL Server to connect to

.PARAMETER SqlCredential
PSCredential object to connect under. If not specified, currend Windows login will be used.

.PARAMETER DataFileCount
Integer of number of datafiles to create. If not specified, function will use logical cores of host.

.PARAMETER DataFileSizeMB
Total data file size in megabytes

.PARAMETER LogFileSizeMB
Log file size in megabyes. If not specified, function will use 25% of total data file size.

.PARAMETER DataPath 
File path to create tempdb data files in. If not specified, current tempdb location will be used.

.PARAMETER LogPath
File path to create tempdb log file in. If not specified, current tempdb location will be used.

.PARAMETER Script
Switch to generate script for tempdb configuration.

.PARAMETER WhatIf
Switch to generate configuration object.
.LINK
https://dbatools.io/Set-SqlTempDBConfiguration

.EXAMPLE
Set-SqlTempDBConfiguration -SqlServer localhost -DataFileSizeMB 1000

Creates tempdb with a number of datafiles equal to the logical cores where
each one is equal to 1000MB divided by number of logical cores and a log file
of 250MB

.EXAMPLE
Set-SqlTempDBConfiguration -SqlServer localhost -DataFileSizeMB 1000 -DataFileCount 8

Creates tempdb with a number of datafiles equal to the logical cores where
each one is equal to 125MB and a log file of 250MB

.EXAMPLE
Set-SqlTempDBConfiguration -SqlServer localhost -DataFileSizeMB 1000 -Script

Provides a SQL script output to configure tempdb according to the passed parameters

.EXAMPLE
Set-SqlTempDBConfiguration -SqlServer localhost -DataFileSizeMB 1000 -Script

Returns PSObject representing tempdb configuration.
#>
[CmdletBinding()]
param(
    [parameter(Mandatory = $true)]
	[Alias("ServerInstance", "SqlInstance")]
    [System.Object]$SqlServer
    ,[System.Management.Automation.PSCredential]$SqlCredential
    ,[int]$DataFileCount
    ,[Parameter(Mandatory=$true)]
     [int]$DataFileSizeMB
    ,[int]$LogFileSizeMB
    ,[string]$DataPath
    ,[string]$LogPath
    ,[Switch]$Script
    ,[Switch]$WhatIf
)
BEGIN{
    [string[]]$scriptout = @()
    Write-Verbose "Connecting to $SqlServer"
    $smosrv = Connect-SqlServer $SqlServer -SqlCredential $SqlCredential
}
PROCESS{
    try{
        #Check cores for datafile count
        $Cores = (Get-WmiObject Win32_Processor -ComputerName $smosrv.ComputerNamePhysicalNetBIOS).NumberOfLogicalProcessors
        if($Cores -gt 8){$Cores = 8}   
                
        #Set DataFileCount if not specified. If specified, check against best practices. 
        if(-not $DataFileCount){
            $DataFileCount = $cores
            Write-Verbose "Data file count set to number of cores: $DataFileCount"
        } else {
            if($DataFileCount -gt $Cores){
                Write-Warning "Data File Count of $DataFileCount exceeds the Logical Core Count of $Cores. This is outside of best practices."
            }
            Write-Verbose "Data file count set explicitly: $DataFileCount"
        }

        $DataFileSizeSingleMB = $([Math]::Floor($DataFileSizeMB/$DataFileCount))
        Write-Verbose "Single data file size (MB): $DataFileSizeSingleMB"

        if($DataPath){
            if( -not (Invoke-Command -ComputerName $smosrv.ComputerNamePhysicalNetBIOS -ScriptBlock {Test-Path $DataPath})){
                throw "$DataPath is an invalid path."
            }
        } else {
            $FilePath = $smosrv.Databases['TempDB'].FileGroups['Primary'].Files[0].FileName
            $DataPath = $FilePath.Substring(0,$FilePath.LastIndexOf('\'))
        }
        Write-Verbose "Using data path: $DataPath"

        if($LogPath){
            if( -not (Invoke-Command -ComputerName $smosrv.ComputerNamePhysicalNetBIOS -ScriptBlock {Test-Path $LogPath})){
                throw "$LogPath is an invalid path."
            }
        } else {
            $FilePath = $smosrv.Databases['TempDB'].LogFiles[0].FileName
            $LogPath = $FilePath.Substring(0,$FilePath.LastIndexOf('\'))
        }
        Write-Verbose "Using log path: $LogPath"

        #Create Configuration Option
        $Config = New-Object psobject
        $Config | Add-Member -MemberType NoteProperty -Name 'SqlServer' -Value $($smosrv.Name)
        $Config | Add-Member -MemberType NoteProperty -Name 'DataFileCount' -Value $DataFileCount
        $Config | Add-Member -MemberType NoteProperty -Name 'DataFileSizeMB' -Value $DataFileSizeMB
        $Config | Add-Member -MemberType NoteProperty -Name 'SingleDataFileSizeMB' -Value $DataFileSizeSingleMB
        $LogSizeMBActual = if(-not $LogFileSizeMB){$([Math]::Floor($DataFileSizeMB/4))}
        $Config | Add-Member -MemberType NoteProperty -Name 'LogSizeMB' -Value $LogSizeMBActual
        $Config | Add-Member -MemberType NoteProperty -Name 'DataPath' -Value $DataPath
        $Config | Add-Member -MemberType NoteProperty -Name 'LogPath' -Value $LogPath

        #If -Whatif, return the config option
        #If not, do the work
        if($WhatIf){
            return $Config
        } 
        else {
            #Check current tempdb. Throw an error if current tempdb is 'larger' than config.
            $CurrentFileCount = $smosrv.Databases['tempdb'].ExecuteWithResults('SELECT count(1) as FileCount FROM sys.database_files WHERE type=0').Tables[0].FileCount
            $ToBigCount = $smosrv.Databases['tempdb'].ExecuteWithResults("SELECT count(1) as FileCount FROM sys.database_files WHERE size/128.0 > $DataFileSizeSingleMB AND type = 0").Tables[0].FileCount

            if($CurrentFileCount -gt $DataFileCount -or $ToBigCount -gt 0){
                $CurrentFileCount
                $DataFileCount
                $ToBigCount

                throw "Current TempDB not suitable to be reconfigured."
            }
            Write-Verbose "TempDB configuration validated."
            #Checks passed, process reconfiguration
                for($i=0;$i -lt $DataFileCount;$i++){
                $file=$smosrv.Databases['TempDB'].FileGroups['Primary'].Files[$i]
                if($file){
                    $filename = ($file.FileName).Substring((($file.FileName).LastIndexof('\'))+1)
                    $logicalname = $file.Name
                    $scriptout += "ALTER DATABASE tempdb MODIFY FILE(name=$logicalname,"`
                                    +"filename='$(Join-Path $DataPath -ChildPath $filename)',size=$DataFileSizeSingleMB`MB,filegrowth=512MB);"
                } else {
                    $scriptout += "ALTER DATABASE tempdb ADD FILE(name=tempdev$i,"`
                                + "filename='$(Join-Path $DataPath -ChildPath "tempdev$i`.ndf")',size=$DataFileSizeSingleMB`MB,filegrowth=512MB);"
                }
            }

            if(-not $LogFileSizeMB){
                $LogFileSizeMB = [Math]::Floor($DataFileSizeMB/4)
            }
            $logfile = $smosrv.Databases['TempDB'].LogFiles[0]
            $filename = ($logfile.FileName).Substring((($logfile.FileName).LastIndexof('\'))+1)
            $logicalname = $logfile.Name
            $scriptout += "ALTER DATABASE tempdb MODIFY FILE(name=$logicalname,"`
                            +"filename='$(Join-Path $DataPath -ChildPath $filename)',size=$LogFileSizeMB`MB,filegrowth=512MB);"

            Write-Verbose "SQL Statement to resize tempdb `n ($scriptout -join "`n")"

            if($Script){
                return $scriptout
            } else {
                $smosrv.Databases['master'].ExecuteNonQuery($scriptout)
                Write-Verbose "TempDB successfully reconfigured"
                Write-Warning "TempDB reconfigured. You must restart the SQL Service for settings to take effect."
            }
        }
    }
    catch{
        Write-Error "$($_.Exception.GetType().FullName) `n $($_.Exception.Message) `n $($_.Exception.InnerException)"
        return $_.Exception
    }
    }
}