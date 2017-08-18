Function Remove-SqlOrphanUser
{
<#
.SYNOPSIS
Drop orphan users with no existing login to map

.DESCRIPTION
An orphan user is defined by a user that does not have their matching login. (Login property = "").
If user is the owner of the schema with the same name and if if the schema does not have any underlying objects the schema will be dropped.
If user owns more than one schema, the owner of the schemas that does not have the same name as the user, will be changed to 'dbo'. If schemas have underlying objects, you must specify the -Force parameter so the user can be dropped.
If exists a login to map the drop will not be performed unless you specify the -Force parameter (only when calling from Repair-SqlOrphanUser.

.PARAMETER SqlServer
The SQL Server instance.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Users
List of users to remove

.PARAMETER Force
If exists any schema which owner is the User, this will force the change of the owner to 'dbo'.
If exists a login to map the drop will not be performed unless you specify this parameter.

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed. 			

.PARAMETER Confirm 		
Prompts you for confirmation before executing any changing operations within the command. 

.NOTES
Tags: Orphan
Original Author: Claudio Silva (@ClaudioESSilva)
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

Will remove from all databases the user OrphanUser EVEN if exists their matching login. First will change any schema that it owns to 'dbo'.

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

    DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $SqlCredential } }

	BEGIN
	{
	}

	PROCESS
	{

        foreach ($Instance in $SqlServer)
		{
            Write-Verbose "Attempting to connect to $Instance"
			try
			{
				$server = Connect-SqlServer -SqlServer $Instance -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "Can't connect to $Instance or access denied. Skipping."
				continue
			}

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
                $StackSource = $CallStack[($CallStack.Count - 2)].Command
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
                            Write-Verbose "Validating users on database '$($db.Name)'"

                            if ($Users.Count -eq 0)
                            {
                                #the third validation will remove from list sql users without login. The rule here is Sid with length higher than 16
                                $Users = $db.Users | Where-Object {$_.Login -eq "" -and ($_.ID -gt 4) -and (($_.Sid.Length -gt 16 -and $_.LoginType -eq [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin) -eq $false)}
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
                                    #the fourth validation will remove from list sql users without login. The rule here is Sid with length higher than 16
                                    $Users = $db.Users | Where-Object {$_.Login -eq "" -and ($_.ID -gt 4) -and ($Users -contains $_.Name) -and (($_.Sid.Length -gt 16 -and $_.LoginType -eq [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin) -eq $false)}
                                }
                            }
                        }

                        if ($Users.Count -gt 0)
                        {
                            Write-Verbose "Orphan users found"
                            foreach ($User in $Users)
                            {
                                $SkipUser = $false

                                $ExistLogin = $null

                                if ($StackSource -ne "Repair-SqlOrphanUser")
                                {
                                    #Need to validate Existing Login because the call does not came from Repair-SqlOrphanUser
                                    $ExistLogin = $server.logins | Where-Object {$_.Isdisabled -eq $False -and
                                                                                       $_.IsSystemObject -eq $False -and
                                                                                       $_.IsLocked -eq $False -and
                                                                                       $_.Name -eq $User.Name }
                                }

                                #Schemas only appears on SQL Server 2005 (v9.0)
                                if ($server.versionMajor -gt 8)
                                {
                                
                                    #Validate if user owns any schema
                                    $Schemas = @()

                                    $Schemas = $db.Schemas | Where-Object {$_.Owner -eq $User.Name}

                                    if(@($Schemas).Count -gt 0)
                                    {
                                        Write-Verbose "User '$($User.Name)' owns one or more schemas."

                                        $AlterSchemaOwner = ""
                                        $DropSchema = ""

                                        foreach ($sch in $Schemas)
                                        {
                                            $NumberObjects = ($db.EnumObjects() | Where-Object {$_.Schema -eq $sch.Name} | Measure-Object).Count

                                            if ($NumberObjects -gt 0)
                                            {
                                                if ($Force)
                                                {
                                                    Write-Verbose "Parameter -Force was used! The schema '$($sch.Name)' have $NumberObjects underlying objects. We will change schema owner to 'dbo' and drop the user."

                                                    if ($Pscmdlet.ShouldProcess($db.Name, "Changing schema '$($sch.Name)' owner to 'dbo'. -Force used."))
				                                    {
                                                        $AlterSchemaOwner += "ALTER AUTHORIZATION ON SCHEMA::[$($sch.Name)] TO [dbo]`r`n"

                                                        [pscustomobject]@{
                                                                            Instance = $server.Name
                                                                            Database = $db.Name
                                                                            SchemaName = $sch.Name
                                                                            Action = "ALTER OWNER"
                                                                            SchemaOwnerBefore = $sch.Owner
                                                                            SchemaOwnerAfter = "dbo"
                                                                        }
                                                    }
                                                }
                                                else
                                                {
                                                    Write-Warning "Schema '$($sch.Name)' owned by user $($User.Name) have $NumberObjects underlying objects. If you want to change the schemas' owner to 'dbo' and drop the user anyway, use -Force parameter. Skipping user '$USer'"
                                                    $SkipUser = $true
                                                    break
                                                }
                                            }
                                            else
                                            {
                                                if ($sch.Name -eq $User.Name)
                                                {
                                                    Write-Verbose "The schema '$($sch.Name)' have the same name as user '$($User.Name)'. Schema will be dropped."

                                                    if ($Pscmdlet.ShouldProcess($db.Name, "Dropping schema '$($sch.Name)'."))
                                                    {
                                                        $DropSchema += "DROP SCHEMA [$($sch.Name)]"

                                                        [pscustomobject]@{
                                                                            Instance = $server.Name
                                                                            Database = $db.Name
                                                                            SchemaName = $sch.Name
                                                                            Action = "DROP"
                                                                            SchemaOwnerBefore = $sch.Owner
                                                                            SchemaOwnerAfter = "N/A"
                                                                        }
                                                    }
                                                }
                                                else
                                                {
                                                    Write-Warning "Schema '$($sch.Name)' does not have any underlying object. Ownership will be changed to 'dbo' so the user can be dropped. Remember to re-check permissions on this schema!"

                                                    if ($Pscmdlet.ShouldProcess($db.Name, "Changing schema '$($sch.Name)' owner to 'dbo'."))
                                                    {
                                                        $AlterSchemaOwner += "ALTER AUTHORIZATION ON SCHEMA::[$($sch.Name)] TO [dbo]`r`n"

                                                        [pscustomobject]@{
                                                                            Instance = $server.Name
                                                                            Database = $db.Name
                                                                            SchemaName = $sch.Name
                                                                            Action = "ALTER OWNER"
                                                                            SchemaOwnerBefore = $sch.Owner
                                                                            SchemaOwnerAfter = "dbo"
                                                                        }
                                                    }
                                                }
                                            }
                                        }

                                    }
                                    else
                                    {
                                        Write-Verbose "User '$($User.Name)' does not own any schema. Will be dropped."
                                    }

                                    $query = "$AlterSchemaOwner `r`n$DropSchema `r`nDROP USER " + $User

                                    Write-Debug $query
                                }
                                else
                                {
                                    $query = "EXEC master.dbo.sp_droplogin @loginame = N'$User'"
                                }

                                if ($ExistLogin)
                                {
                                    if (!$SkipUser)
                                    {
                                        if ($Force)
                                        {
                                            if ($Pscmdlet.ShouldProcess($db.Name, "Dropping user '$($User.Name)' using -Force"))
				                            {
                                                $server.Databases[$db.Name].ExecuteNonQuery($query) | Out-Null
												Write-Output "User '$($User.Name)' was dropped from $($db.Name). -Force parameter was used!"
                                            }
                                        }
                                        else
                                        {
                                            Write-Warning "Orphan user $($User.Name) has a matching login. The user will not be dropped. If you want to drop anyway, use -Force parameter."
                                            Continue
                                        }
                                    }
                                }
                                else
                                {
                                    if (!$SkipUser)
                                    {
                                        if ($Pscmdlet.ShouldProcess($db.Name, "Dropping user '$($User.Name)'"))
				                        {
                                            $server.Databases[$db.Name].ExecuteNonQuery($query) | Out-Null
											Write-Output "User '$($User.Name)' was dropped from $($db.Name)."
                                        }
                                    }
                                }
                            }
                        }
                        else
                        {
                            Write-Verbose "No orphan users found on database '$($db.Name)'."
                        }
                        #reset collection
                        $Users = $null
                    }
                    catch
                    {
                        Write-Error $_
                    }
                }
            }
            else
            {
                Write-Verbose "There are no databases to analyse."
            }
        }
	}

	END
	{
		$server.ConnectionContext.Disconnect()

        $totaltime = ($start.Elapsed)

        #If the call don't come from Repair-SqlOrphanUser function, show elapsed time
		if ($StackSource -ne "Repair-SqlOrphanUser")
        {
           Write-Verbose "Total Elapsed time: $totaltime"
        }
	}
}
