function Set-DbaStartupParameter {
<#
.SYNOPSIS
Sets the Startup Parameters for a SQL Server instance

.DESCRIPTION
Modifies the startup parameters for a specified SQL Server SqlInstance

For full details of what each parameter does, please refer to this MSDN article - https://msdn.microsoft.com/en-us/library/ms190737(v=sql.105).aspx

.PARAMETER SqlInstance
The SQL Server instance to be modified

.PARAMETER Credential
Windows credential with permission to log on to the server running the SQL instance

.PARAMETER MasterData
Path to the data file for the Master database

.PARAMETER MasterLog
Path to the log file for the Master database

.PARAMETER ErrorLog
path to the SQL Server error log file 

.PARAMETER TraceFlags
A comma seperated list of TraceFlags to be applied at SQL Server startup
By default these will be appended to any existing trace flags set

.PARAMETER CommandPromptStart
	
Shortens startup time when starting SQL Server from the command prompt. Typically, the SQL Server Database Engine starts as a service by calling the Service Control Manager. 
Because the SQL Server Database Engine does not start as a service when starting from the command prompt

.PARAMETER MinimalStart
	
Starts an instance of SQL Server with minimal configuration. This is useful if the setting of a configuration value (for example, over-committing memory) has 
prevented the server from starting. Starting SQL Server in minimal configuration mode places SQL Server in single-user mode

.PARAMETER MemoryToReserve
Specifies an integer number of megabytes (MB) of memory that SQL Server will leave available for memory allocations within the SQL Server process, 
but outside the SQL Server memory pool. The memory outside of the memory pool is the area used by SQL Server for loading items such as extended procedure .dll files, 
the OLE DB providers referenced by distributed queries, and automation objects referenced in Transact-SQL statements. The default is 256 MB.

.PARAMETER SingleUser
Start Sql Server in single user mode

.PARAMETER NoLoggingToWinEvents
Don't use Windows Application events log

.PARAMETER StartAsNamedInstance
Allows you to start a named instance of SQL Server

.PARAMETER DisableMonitoring

.PARAMETER IncreasedExtents
Increases the number of extents that are allocated for each file in a filegroup. T

.PARAMETER TraceFlagsOverride
Overrides the default behavious and replaces any existing trace flags. If not trace flags specified will just remove existing ones

.PARAMETER StartUpConfig
Pass in a previously saved SQL Instance startUpconfig
using this parameter will set TraceFlagsOverride to true, so existing Trace Flags will be overridden

.NOTES
Original Author: Stuart Moore (@napalmgram), stuart-moore.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE 
Set-DbaStartupParameter -SqlServer server1\instance1 -SingleUser

Will configure the SQL Instance server1\instance1 to startup up in Single User mode at next startup
	
.EXAMPLE
Set-DbaStartupParameter -SqlServer server1\instance1 -SingleUser -TraceFlags 8032,8048
This will appened Trace Flags 8032 and 8048 to the startup paramters

.EXAMPLE
Set-DbaStartupParameter -SqlServer server1\instance1 -SingleUser -TraceFlags 8032,8048 -TraceFlagsOverride

This will set Trace Flags 8032 and 8048 to the startup paramters, removing any existing Trace Flags

.EXAMPLE

$StartupConfig = Get-DbaStartupParameter -SqlServer server1\instance1
Set-DbaStartupParameter -SqlServer server1\instance1 -SingleUser -NoLoggingToWinEvents
Stop-DbaService -SqlServer server1\instance1 -Service SqlServer
Start-DbaService -SqlServer server1\instance1 -Service SqlServer
#Do Some work
Set-DbaStartupParameter -SqlServer server1\instance1 -StartUpConfig $StartUpConfig
Stop-DbaService -SqlServer server1\instance1 -Service SqlServer
Start-DbaService -SqlServer server1\instance1 -Service SqlServer

In this example we take a copy of the existing startup configuration of server1\instance1

We then change the startup parameters ahead of some work

After the work has been completed, we can push the original startup parameters back to server1\instance1 and resume normal operation

#>
	[CmdletBinding(SupportsShouldProcess=$true)]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[PSCredential]$Credential,
        [string]$MasterData,
        [string]$MasterLog,
        [string]$ErrorLog,
        [string]$TraceFlags,
        [switch]$CommandPromptStart,
        [switch]$MinimalStart,
        [int]$MemoryToReserve,
        [switch]$SingleUser,
        [string]$SingleUserDetails,
        [switch]$NoLoggingToWinEvents,
        [switch]$StartAsNamedInstance,
        [switch]$DisableMonitoring,
        [switch]$IncreasedExtents,
        [switch]$TraceFlagsOverride,
        [object]$StartUpConfig

	)
    $FunctionName =(Get-PSCallstack)[0].Command
    #Get Current parameters:
    $CurrentStartup = Get-DbaStartupParameter -SqlServer $SqlServer -SqlCredential $Credential
    #clone for safety

    if ('startUpconfig' -in $PsBoundParameters.keys)
    {
        Write-Verbose "$FunctionName - Config object passed in"
        $NewStartup = $StartUpConfig
        $TraceFlagsOverride = $true
    }
    else
    {    
        Write-Verbose "$FunctionName - Parameters passed in"
        $NewStartup = $CurrentStartup.PSObject.copy()
        foreach ($param in ($PsBoundParameters.keys | ?{$_ -in ($NewStartup.PSObject.Properties.name)}))
        {
            if ($PsBoundParameters.item($param) -ne $NewStartup.$param )
            {
                $NewStartup.$param = $PsBoundParameters.item($param) 
            }

        }
        Write-Verbose "su = $($NewStartup.SingleUser)"
    }
    if (!($CurrentStartup.SingleUser))
    {       
        Write-Verbose "$FunctionName - Sql instance is presently configured for single user, skipping path validation" 
        if ($NewStartup.Masterdata.length -gt 0)
        {
            if (Test-SqlPath -SqlServer $SqlServer -SqlCredential $Credential -Path (Split-Path $NewStartup.MasterData -Parent))
            {
                $ParameterString += "-d$($NewStartup.MasterData);"
            }
            else
            {
                Write-Warning "$FunctionName - Specified folder for Master Data file is not reachable by SQL"
                return
            }
        }
        else
        {
            Stop-Function -message -message "MasterData value must be provided" -silent:$true
        }
        if($NewStartup.ErrorLog.length -gt 0)
        {
            if (Test-SqlPath -SqlServer $SqlServer -SqlCredential $Credential -Path (Split-Path $NewStartup.ErrorLog -Parent))
            {
                $ParameterString += "-e$($NewStartup.ErrorLog);"
            }
            else
            {
                Write-Warning "$FunctionName - Specified folder for ErrorLog  file is not reachable by SQL"
                return
            }
        }
        else
        {
            Stop-Function -message "ErrorLog value must be provided"
        }
        if ($NewStartup.MasterLog.Length -gt 0)
        {
            if (Test-SqlPath -SqlServer $SqlServer -SqlCredential $Credential -Path (Split-Path $NewStartup.MasterLog -Parent))
            {
                $ParameterString += "-l$($NewStartup.MasterLog);"
            }
            else
            {
                Write-Warning "$FunctionName - Specified folder for Master Log  file is not reachable by SQL"
                return
            }
        }
        else
        {
            Stop-Function -message "MasterLog value must be provided." -silent:$true
        }
    }
    else
    {
        if ($NewStartup.MasterData.Length -gt 0)
        {
            $ParameterString += "-d$($NewStartup.MasterData);"
        }
        else
        {
            Stop-Function -message "Must have a value for MasterData" -silent:$true
        }
        if ($NewStartup.ErrorLog.Length -gt 0)
        {
            $ParameterString += "-e$($NewStartup.ErrorLog);"
        }
        else
        {
            Stop-Function -message "Must have a value for Errorlog" -silent:$true
        }
        if ($NewStartup.MasterLog.Length -gt 0)
        {
            $ParameterString += "-l$($NewStartup.MasterLog);"
        } 
        else
        {
            Stop-Function -message "Must have a value for MsterLog" -silent:$true
        } 
    }

    if ($NewStartup.CommandPromptStart)
    {
        $ParameterString += "-c;"
    }
    if ($NewStartup.MinimalStart)
    {
        $ParameterString += "-f;"
    }
    if ($NewStartup.MemoryToReserve -notin ($null,0))
    {
        $ParameterString += "-g$($NewStartup.MemoryToReserve)"
    }
    if  ($NewStartup.SingleUser)
    {
        if ($SingleUserDetails.length -gt 0)
        {
            if ($SingleUserDetails -match ' ')
            {
                $SingleUserDetails = """$SingleUserDetails"""
            }
            $ParameterString += "-m$SingleUserDetails;"
        }
        else
        {
            $ParameterString += "-m;"
        }
    }
    if ($NewStartup.NoLoggingToWinEvents)
    {
        $ParameterString += "-n";
    }
    If ($NewStartup.StartAsNamedInstance)
    {
        $ParameterString += "-s;"
    }
    if ($NewStartup.DisableMonitoring)
    {
        $ParameterString += "-x;"
    }
    if ($NewStartup.IncreasedExtents)
    {
        $ParameterString += "-E;"
    }
    if($TraceFlagsOverride -and 'TraceFlags' -in $PsBoundParameters.keys)
    {
        $NewStartup.TraceFlags = $TraceFlags
        $ParameterString += (($TraceFlags.split(',') | Foreach {"-T$_"}) -join ';')+";"
    }
    else 
    {
        if ('TraceFlags'  -in $PsBoundParameters.keys)
        {
            
            $oldflags = @($CurrentStartup.TraceFlags) -split ','
            $newflags = @($TraceFlags) -split ','
            $oldflags + $newflags
            $NewStartup.TraceFlags = ($oldFlags + $newflags | Sort-Object -Unique) -join ','
            $NewStartup.traceflags
        }
        else
        {
            $NewStartup.TraceFlags =  if($CurrentStartup.TraceFlags -eq 'None'){}else{$CurrentStartup.TraceFlags} 
        }
        If ($NewStartup.TraceFlags.Length -ne 0)
        {
            $ParameterString += (($NewStartup.TraceFlags.split(',') | Foreach {"-T$_"}) -join ';')+";"
        }
    }

    $servername, $instancename = ($sqlserver.Split('\'))
    Write-Verbose "Attempting to connect to $instancename on $servername"
    
    if ($instancename.Length -eq 0) { $instancename = "MSSQLSERVER" }
    
    $displayname = "SQL Server ($instancename)"
    
    $Scriptblock = {
                $servername = $args[0]
                $displayname = $args[1]
                $ParameterString = $args[2]
					
                $wmisvc = $wmi.Services | Where-Object { $_.DisplayName -eq $displayname }
                $wmisvc.StartupParameters = $ParameterString
                $wmisvc.Alter()
                $wmisvc.Refresh()
                if ($wmisvc.StartupParameters -eq $ParameterString)
                {
                    $true
                }
                else
                {
                    $false
                }
    }
    Write-Debug "$FunctionName - Old ParameterString - $($CurrentStartup.ParameterString)"
    Write-Debug "$FunctionName - New ParameterString - $ParameterString"
    if ($pscmdlet.ShouldProcess("Setting Sql Server start parameters on $SqlServer to $ParameterString")) {
        $response = Invoke-ManagedComputerCommand -ComputerName $servername -Credential $credential -ScriptBlock $Scriptblock -ArgumentList $servername, $displayname, $ParameterString
    }  
    if ($response)
    {   
        Write-Warning "$FunctionName - Startup parameters changed on $SqlServer `n Will only take effect after a restart"
    }
    else
    {
        Write-Warning "$FunctionName - Startup parameters failed to change on $SqlServer "
    }
    

}