Function Remove-SqlOrphanUser
{
<#
.SYNOPSIS
Drop orphan users with no existing login to map

.DESCRIPTION
An orphan user is defined by a user that does not have their matching login. (Login property = "").
If exists a login to map the drop will not be performed unless you specify the -Force parameter.
	
.PARAMETER SqlServer
The SQL Server instance.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Users
List of users to remove

.PARAMETER Force
If exists a login to map the drop will not be performed unless you specify this parameter.

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
https://dbatools.io/Remove-SqlOrphanUser

.EXAMPLE
Remove-SqlOrphanUser -SqlServer sql2005 

Will find and drop all orphan users without matching login of all databases present on server 'sql2005'

.EXAMPLE   
Remove-SqlOrphanUser -SqlServer sqlserver2014a -SqlCredential $cred
	
Will find and drop all orphan users without matching login of all databases present on server 'sqlserver2014a'. Will be verified using SQL credentials. 
	
.EXAMPLE   
Remove-SqlOrphanUser -SqlServer sqlserver2014a -Databases db1, db2 -Force

Will find all and drop orphan users even if exists their matching login on both db1 and db2 databases

.EXAMPLE   
Remove-SqlOrphanUser -SqlServer sqlserver2014a -Users OrphanUser

Will remove from all databases the user OrphanUser only if not have their matching login

.EXAMPLE   
Remove-SqlOrphanUser -SqlServer sqlserver2014a -Users OrphanUser -Force

Will remove from all databases the user OrphanUser EVEN if exists their matching login.
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
        [object]$SqlCredential,
        [parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [object[]]$Users,
        [switch]$Force
	)

    DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer -SqlCredential $SqlCredential } }
	
	BEGIN
	{
        Write-Output "Attempting to connect to Sql Server.."
		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	}
	
	PROCESS
	{

        # Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		
        if ($databases.Count -eq 0)
        {
            $databases = $server.Databases | Where-Object {$_.IsSystemObject -eq $false -and $_.IsAccessible -eq $true}
        }
        else
        {
            if ($pipedatabase.Length -gt 0)
		    {
			    $Source = $pipedatabase[0].parent.name
			    $databases = $pipedatabase.name
		    }
            else
            {
                $databases = $server.Databases | Where-Object {$_.IsSystemObject -eq $false -and $_.IsAccessible -eq $true -and ($databases -contains $_.Name)}
            }
        }


        $CallStack = Get-PSCallStack | Select-Object -Property *
        if ($CallStack.Count -eq 1) 
        {
            $StackSource = $CallStack[0].Command
        } 
        else 
        {
            #-2 because index base is 0 and we want the one before the last (the last is the actual command)
            $StackSource = $CallStack[($CallStack.Count – 2)].Command
        }

        if ($databases.Count -gt 0)
        {
            $start = [System.Diagnostics.Stopwatch]::StartNew()

            foreach ($db in $databases)
            {
                try
                {
                    #if SQL 2012 or higher only validate databases with ContainmentType = NONE
                    if ($server.versionMajor -gt 10)
		            {
                        if ($db.ContainmentType -ne [Microsoft.SqlServer.Management.Smo.ContainmentType]::None)
                        {
                            Write-Warning "Database '$db' is a contained database. Contained databases can't have orphaned users. Skipping validation."
                            Continue
                        }
                    }

                    if ($StackSource -eq "Repair-SqlOrphanUser")
                    {
                        Write-Verbose "Call origin: Repair-SqlOrphanUser"
                        #Will use collection from parameter ($Users)
                    }
                    else
                    {
                        Write-Output "Validating users on database '$db'"

                        if ($Users.Count -eq 0)
                        {
                            $Users = $db.Users | Where {$_.Login -eq "" -and ("dbo","guest","sys","INFORMATION_SCHEMA" -notcontains $_.Name)}
                        }
                        else
                        {
                            if ($pipedatabase.Length -gt 0)
		                    {
			                    $Source = $pipedatabase[0].parent.name
			                    $Users = $pipedatabase.name
		                    }
                            else
                            {
                                $Users = $db.Users | Where {$_.Login -eq "" -and ($Users -contains $_.Name)}
                            }
                        }
                    }

                    if ($Users.Count -gt 0)
                    {
                        Write-Output "Orphan users found"
                        foreach ($User in $Users)
                        {
                            
                            if ($server.versionMajor -gt 8)
                            {
                                $query = "DROP USER " + $User
                            }
                            else
                            {
                                $query = "EXEC master.dbo.sp_droplogin @loginame = N'$User'"
                            }

                            $ExistLogin = $null

                            if ($StackSource -ne "Repair-SqlOrphanUser")
                            {
                                #do not need to validate Existing Login because the call come from Repair-SqlOrphanUser
                                $ExistLogin = $server.logins | Where-Object {$_.Isdisabled -eq $False -and 
                                                                                   $_.IsSystemObject -eq $False -and 
                                                                                   $_.IsLocked -eq $False -and 
                                                                                   $_.Name -eq $User.Name }
                            }

                            if ($ExistLogin)
                            {
                                if ($Force)
                                {
                                    if ($Pscmdlet.ShouldProcess($db.Name, "Dropping user '$($User.Name)' using -Force"))
				                    {
                                        $server.Databases[$db.Name].ExecuteNonQuery($query) | Out-Null
                                        Write-Output "User '$($User.Name)' was dropped. -Force parameter was used!"
                                    }
                                }
                                else
                                {
                                    Write-Warning "Orphan user $($User.Name) have a matching login. The user will not be dropped. If you want to drop anyway, use -Force parameter."
                                    Continue
                                }
                            }
                            else
                            {
                                if ($Pscmdlet.ShouldProcess($db.Name, "Dropping user '$($User.Name)'"))
				                {
                                    $server.Databases[$db.Name].ExecuteNonQuery($query) | Out-Null
                                    Write-Output "User '$($User.Name)' was dropped."
                                }
                            }
                        }
                    }
                    else
                    {
                        Write-Output "No orphan users found on database '$db'"
                    }
                    #reset collection
                    $Users = $null
                }
                catch
                {
                    throw $_
                }
            }
        }
        else
        {
            Write-Output "There are no databases to analyse."
        }
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()

        $totaltime = ($start.Elapsed)

        #If the call don't come from Repair-SqlOrphanUser function, show elapsed time
		if ($StackSource -ne "Repair-SqlOrphanUser")
        {
           Write-Output "Total Elapsed time: $totaltime"
        }
	}
}