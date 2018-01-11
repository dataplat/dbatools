#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

function Set-DbaStartupParameter {
    <#
.SYNOPSIS
Sets the Startup Parameters for a SQL Server instance

.DESCRIPTION
Modifies the startup parameters for a specified SQL Server Instance

For full details of what each parameter does, please refer to this MSDN article - https://msdn.microsoft.com/en-us/library/ms190737(v=sql.105).aspx

.PARAMETER SqlInstance
The SQL Server instance to be modified

If the Sql Instance is offline path parameters will be ignored as we cannot test the instance's access to the path. If you want to force this to work then please use the Force switch

.PARAMETER SqlCredential
Windows or Sql Login Credential with permission to log into the SQL instance

.PARAMETER Credential
Windows Credential with permission to log on to the server running the SQL instance

.PARAMETER MasterData
Path to the data file for the Master database

Will be ignored if SqlInstance is offline or the Offline switch is set. To override this behaviour use the Force switch. This is to ensure you understand the risk as we cannot validate the path if the instance is offline

.PARAMETER MasterLog
Path to the log file for the Master database

Will be ignored if SqlInstance is offline or the Offline switch is set. To override this behaviour use the Force switch. This is to ensure you understand the risk as we cannot validate the path if the instance is offline

.PARAMETER ErrorLog
path to the SQL Server error log file

Will be ignored if SqlInstance is offline or the Offline switch is set. To override this behaviour use the Force switch. This is to ensure you understand the risk as we cannot validate the path if the instance is offline

.PARAMETER TraceFlags
A comma separated list of TraceFlags to be applied at SQL Server startup
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
Disables the following monitoring features:

SQL Server performance monitor counters
Keeping CPU time and cache-hit ratio statistics
Collecting information for the DBCC SQLPERF command
Collecting information for some dynamic management views
Many extended-events event points

** Warning *\* When you use the -x startup option, the information that is available for you to diagnose performance and functional problems with SQL Server is greatly reduced.

.PARAMETER SingleUserDetails
The username for single user

.PARAMETER IncreasedExtents
Increases the number of extents that are allocated for each file in a filegroup.

.PARAMETER TraceFlagsOverride
Overrides the default behaviour and replaces any existing trace flags. If not trace flags specified will just remove existing ones

.PARAMETER StartUpConfig
Pass in a previously saved SQL Instance startUpconfig
using this parameter will set TraceFlagsOverride to true, so existing Trace Flags will be overridden

.PARAMETER Offline
Setting this switch will try perform the requested actions without conntect to the SQL Server Instance, this will speed things up if you know the Instance is offline.

When working offline, path inputs (MasterData, MasterLog and ErrorLog) will be ignored, unless Force is specifiec

.PARAMETER Force
By default we test the values passed in via MasterData, MasterLog, ErrorLog

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER EnableException
By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Author: Stuart Moore (@napalmgram), stuart-moore.com
Tags:
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser

Will configure the SQL Instance server1\instance1 to startup up in Single User mode at next startup

.EXAMPLE
Set-DbaStartupParameter -SqlInstance sql2016 -IncreasedExtents

Will configure the SQL Instance sql2016 to IncreasedExtents = True (-E)

.EXAMPLE
Set-DbaStartupParameter -SqlInstance sql2016  -IncreasedExtents:$false -WhatIf

Shows what would happen if you attempted to configure the SQL Instance sql2016 to IncreasedExtents = False (no -E)

.EXAMPLE
Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser -TraceFlags 8032,8048
This will append Trace Flags 8032 and 8048 to the startup parameters

.EXAMPLE
Set-DbaStartupParameter -SqlInstance sql2016 -SingleUser:$false -TraceFlagsOverride
This will remove all trace flags and set SinguleUser to false

.EXAMPLE
Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser -TraceFlags 8032,8048 -TraceFlagsOverride

This will set Trace Flags 8032 and 8048 to the startup parameters, removing any existing Trace Flags

.EXAMPLE
Set-DbaStartupParameter -SqlInstance sql2016 -SingleUser:$false -TraceFlagsOverride -Offline

This will remove all trace flags and set SinguleUser to false from an offline instance

.EXAMPLE
Set-DbaStartupParameter -SqlInstance sql2016 -ErrorLog c:\Sql\ -Offline

This will attempt to change the ErrorLog path to c:\sql\. However, with the offline switch this will not happen. To force it, use the -Force switch like so:

Set-DbaStartupParameter -SqlInstance sql2016 -ErrorLog c:\Sql\ -Offline -Force

.EXAMPLE

$StartupConfig = Get-DbaStartupParameter -SqlInstance server1\instance1
Set-DbaStartupParameter -SqlInstance server1\instance1 -SingleUser -NoLoggingToWinEvents
#Restart your SQL instance with the tool of choice
#Do Some work
Set-DbaStartupParameter -SqlInstance server1\instance1 -StartUpConfig $StartUpConfig
#Restart your SQL instance with the tool of choice and you're back to normal

In this example we take a copy of the existing startup configuration of server1\instance1

We then change the startup parameters ahead of some work

After the work has been completed, we can push the original startup parameters back to server1\instance1 and resume normal operation

#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param ([parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string]$MasterData,
        [string]$MasterLog,
        [string]$ErrorLog,
        [string[]]$TraceFlags,
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
        [object]$StartUpConfig,
        [switch]$Offline,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )
    process {

        if (-not $Offline) {
            try {
                Write-Message -Level VeryVerbose -Message "Connecting to $SqlInstance" -Target $SqlInstance
                $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            }
            catch {
                Write-Message -Level Warning -Message "Failed to connect to $SqlInstance, will try to work with just WMI. Path options will be ignored unless Force was indicated"
                $Server = $SqlInstance
                $Offline = $true
            }
        }
        else {
            Write-Message -Level Verbose -Message "Offline switch set, proceeding with just WMI"
            $Server = $SqlInstance
        }

        #Get Current parameters:
        $currentstartup = Get-DbaStartupParameter -SqlInstance $server -Credential $Credential
        $originalparamstring = $currentstartup.ParameterString

        Write-Message -Level Output -Message "Original startup parameter string: $originalparamstring"

        if ('startUpconfig' -in $PsBoundParameters.keys) {
            Write-Message -Level VeryVerbose -Message "StartupObject passed in"
            $newstartup = $StartUpConfig
            $TraceFlagsOverride = $true
        }
        else {
            Write-Message -Level VeryVerbose -Message "Parameters passed in"
            $newstartup = $currentstartup.PSObject.copy()
            foreach ($param in ($PsBoundParameters.keys | Where-Object { $_ -in ($newstartup.PSObject.Properties.name) })) {
                if ($PsBoundParameters.item($param) -ne $newstartup.$param) {
                    $newstartup.$param = $PsBoundParameters.item($param)
                }
            }
        }

        if (!($currentstartup.SingleUser)) {

            if ($newstartup.Masterdata.length -gt 0) {
                if ($Offline -and -not $Force) {
                    Write-Message -Level Warning -Message "Working offline, skipping untested MasterData path"
                    $ParameterString += "-d$($CurrentStartup.MasterData);"

                }
                else {
                    if ($Force) {
                        $ParameterString += "-d$($newstartup.MasterData);"
                    }
                    elseif (Test-DbaSqlPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newstartup.MasterData -Parent)) {
                        $ParameterString += "-d$($newstartup.MasterData);"
                    }
                    else {
                        Stop-Function -Message "Specified folder for Master Data file is not reachable by instance $SqlInstance"
                        return
                    }
                }
            }
            else {
                Stop-Function -Message "MasterData value must be provided"
                return
            }

            if ($newstartup.ErrorLog.length -gt 0) {
                if ($Offline -and -not $Force) {
                    Write-Message -Level Warning -Message "Working offline, skipping untested ErrorLog path"
                    $ParameterString += "-e$($CurrentStartup.ErrorLog);"
                }
                else {
                    if ($Force) {
                        $ParameterString += "-e$($newstartup.ErrorLog);"
                    }
                    elseif (Test-DbaSqlPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newstartup.ErrorLog -Parent)) {
                        $ParameterString += "-e$($newstartup.ErrorLog);"
                    }
                    else {
                        Stop-Function -Message "Specified folder for ErrorLog  file is not reachable by $SqlInstance"
                        return
                    }
                }
            }
            else {
                Stop-Function -Message "ErrorLog value must be provided"
                return
            }

            if ($newstartup.MasterLog.Length -gt 0) {
                if ($offline -and -not $Force) {
                    Write-Message -Level Warning -Message "Working offline, skipping untested MasterLog path"
                    $ParameterString += "-l$($CurrentStartup.MasterLog);"
                }
                else {
                    if ($Force) {
                        $ParameterString += "-l$($newstartup.MasterLog);"
                    }
                    elseif (Test-DbaSqlPath -SqlInstance $server -SqlCredential $SqlCredential -Path (Split-Path $newstartup.MasterLog -Parent)) {
                        $ParameterString += "-l$($newstartup.MasterLog);"
                    }
                    else {
                        Stop-Function -Message "Specified folder for Master Log  file is not reachable by $SqlInstance"
                        return
                    }
                }
            }
            else {
                Stop-Function -Message "MasterLog value must be provided."
                return
            }
        }
        else {

            Write-Message -Level Verbose -Message "Sql instance is presently configured for single user, skipping path validation"
            if ($newstartup.MasterData.Length -gt 0) {
                $ParameterString += "-d$($newstartup.MasterData);"
            }
            else {
                Stop-Function -Message "Must have a value for MasterData"
                return
            }
            if ($newstartup.ErrorLog.Length -gt 0) {
                $ParameterString += "-e$($newstartup.ErrorLog);"
            }
            else {
                Stop-Function -Message "Must have a value for Errorlog"
                return
            }
            if ($newstartup.MasterLog.Length -gt 0) {
                $ParameterString += "-l$($newstartup.MasterLog);"
            }
            else {
                Stop-Function -Message "Must have a value for MsterLog"
                return
            }
        }

        if ($newstartup.CommandPromptStart) {
            $ParameterString += "-c;"
        }
        if ($newstartup.MinimalStart) {
            $ParameterString += "-f;"
        }
        if ($newstartup.MemoryToReserve -notin ($null, 0)) {
            $ParameterString += "-g$($newstartup.MemoryToReserve)"
        }
        if ($newstartup.SingleUser) {
            if ($SingleUserDetails.length -gt 0) {
                if ($SingleUserDetails -match ' ') {
                    $SingleUserDetails = """$SingleUserDetails"""
                }
                $ParameterString += "-m$SingleUserDetails;"
            }
            else {
                $ParameterString += "-m;"
            }
        }
        if ($newstartup.NoLoggingToWinEvents) {
            $ParameterString += "-n;"
        }
        If ($newstartup.StartAsNamedInstance) {
            $ParameterString += "-s;"
        }
        if ($newstartup.DisableMonitoring) {
            $ParameterString += "-x;"
        }
        if ($newstartup.IncreasedExtents) {
            $ParameterString += "-E;"
        }
        if ($newstartup.TraceFlags -eq 'None') {
            $newstartup.TraceFlags = ''
        }
        if ($TraceFlagsOverride -and 'TraceFlags' -in $PsBoundParameters.keys) {
            if ($null -ne $TraceFlags -and '' -ne $TraceFlags) {
                $newstartup.TraceFlags = $TraceFlags -join ','
                $ParameterString += (($TraceFlags.split(',') | ForEach-Object { "-T$_" }) -join ';') + ";"
            }
        }
        else {
            if ('TraceFlags' -in $PsBoundParameters.keys) {
                if ($null -eq $TraceFlags) { $TraceFlags = '' }
                $oldflags = @($currentstartup.TraceFlags) -split ',' | Where-Object { $_ -ne 'None' }
                $newflags = $TraceFlags
                $newflags = $oldflags + $newflags
                $newstartup.TraceFlags = ($oldFlags + $newflags | Sort-Object -Unique) -join ','
            }
            elseif ($TraceFlagsOverride) {
                $newstartup.TraceFlags = ''
            }
            else {
                $newstartup.TraceFlags = if ($currentstartup.TraceFlags -eq 'None') { }
                else { $currentstartup.TraceFlags -join ',' }
            }
            If ($newstartup.TraceFlags.Length -ne 0) {
                $ParameterString += (($newstartup.TraceFlags.split(',') | ForEach-Object { "-T$_" }) -join ';') + ";"
            }
        }

        $instance = $SqlInstance.ComputerName
        $instancename = $SqlInstance.InstanceName
        Write-Message -Level Verbose -Message "Attempting to connect to $instancename on $instance"

        if ($instancename.Length -eq 0) { $instancename = "MSSQLSERVER" }

        $displayname = "SQL Server ($instancename)"

        if ($originalparamstring -eq "$ParameterString" -or "$originalparamstring;" -eq "$ParameterString") {
            Stop-Function -Message "New parameter string would be the same as the old parameter string. Nothing to do." -Target $ParameterString
            return
        }

        $Scriptblock = {
            $instance = $args[0]
            $displayname = $args[1]
            $ParameterString = $args[2]

            $wmisvc = $wmi.Services | Where-Object { $_.DisplayName -eq $displayname }
            $wmisvc.StartupParameters = $ParameterString
            $wmisvc.Alter()
            $wmisvc.Refresh()
            if ($wmisvc.StartupParameters -eq $ParameterString) {
                $true
            }
            else {
                $false
            }
        }

        if ($pscmdlet.ShouldProcess("Setting Sql Server start parameters on $SqlInstance to $ParameterString")) {
            try {
                if ($Credential) {
                    $response = Invoke-ManagedComputerCommand -ComputerName $instance -Credential $Credential -ScriptBlock $Scriptblock -ArgumentList $instance, $displayname, $ParameterString -EnableException
                    $output = Get-DbaStartupParameter -SqlInstance $server -Credential $Credential -EnableException
                    Add-Member -Force -InputObject $output -MemberType NoteProperty -Name OriginalStartupParameters -Value $originalparamstring
                }
                else {
                    $response = Invoke-ManagedComputerCommand -ComputerName $instance -ScriptBlock $Scriptblock -ArgumentList $instance, $displayname, $ParameterString -EnableException
                    $output = Get-DbaStartupParameter -SqlInstance $server -EnableException
                    Add-Member -Force -InputObject $output -MemberType NoteProperty -Name OriginalStartupParameters -Value $originalparamstring
                }

                $output

                Write-Message -Level Output -Message "Startup parameters changed on $SqlInstance. You must restart SQL Server for changes to take effect."
            }
            catch {
                Stop-Function -Message "Startup parameters failed to change on $SqlInstance. " -Target $SqlInstance -ErrorRecord $_
                return
            }
        }
    }
}
