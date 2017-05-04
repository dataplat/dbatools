Function Export-SqlUser
{
<#
.SYNOPSIS
Exports users creation and its permissions to a T-SQL file or host.

.DESCRIPTION
Exports users creation and its permissions to a T-SQL file or host. Export includes user, create and add to role(s), database level permissions, object level permissions.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER SqlInstance
The SQL Server instance name. SQL Server 2000 and above supported.
	
.PARAMETER SqlCredential
Allows you to login to servers using alternative credentials

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter

Windows Authentication will be used if SqlCredential is not specified

.PARAMETER User 
Export only the specified database user(s). If not specified will export all users from the database(s)

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER DestinationVersion
To say to which version the script should be generated. If not specified will use database compatibility level

.PARAMETER FilePath
The file to write to.

.PARAMETER NoClobber
Do not overwrite file
	
.PARAMETER Append
Append to file

.EXAMPLE
Export-SqlUser -SqlServer sql2005 -FilePath C:\temp\sql2005-users.sql

Exports SQL for the users in server "sql2005" and writes them to the file "C:\temp\sql2005-users.sql"

.EXAMPLE
Export-SqlUser -SqlServer sqlserver2014a $scred -FilePath C:\temp\users.sql -Append

Authenticates to sqlserver2014a using SQL Authentication. Exports all users to C:\temp\users.sql, and appends to the file if it exists. If not, the file will be created.

.EXAMPLE
Export-SqlUser -SqlServer sqlserver2014a -User User1, User2 -FilePath C:\temp\users.sql

Exports ONLY users User1 and User2 fron sqlsever2014a to the file  C:\temp\users.sql

.EXAMPLE
Export-SqlUser -SqlServer sqlserver2008 -User User1 -FilePath C:\temp\users.sql -DestinationVersion SQLServer2016

Exports user User1 fron sqlsever2008 to the file  C:\temp\users.sql with sintax to run on SQL Server 2016

.NOTES
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
https://dbatools.io/Export-SqlUser
#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    [OutputType([String])]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[string]$SqlInstance,
        [object[]]$User,
        [ValidateSet('SQLServer2000', 'SQLServer2005', 'SQLServer2008/2008R2', 'SQLServer2012', 'SQLServer2014', 'SQLServer2016')]
        [string]$DestinationVersion,
		[Alias("OutFile", "Path","FileName")]
		[string]$FilePath,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[Alias("NoOverwrite")]
		[switch]$NoClobber,
		[switch]$Append
	)
	
	DynamicParam 
    { 
        if ($SqlInstance)
		{
            return Get-ParamSqlDatabases -SqlServer $SqlInstance -SqlCredential $SqlCredential
		}
    }
	BEGIN
	{
        if ($FilePath.Length -gt 0)
		{
			if ($FilePath -notlike "*\*") { $FilePath = ".\$filepath" }
			$directory = Split-Path $FilePath
			$exists = Test-Path $directory
			
			if ($exists -eq $false)
			{
				throw "Parent directory $directory does not exist"
			}
			
			Write-Output "--Attempting to connect to SQL Servers.."
		}

        $sourceserver = Connect-SqlServer -SqlServer $SqlInstance -SqlCredential $SqlCredential

		$outsql = @()

        $versions = @{
                'SQLServer2000' = 'Version80'
                'SQLServer2005' = 'Version90'
                'SQLServer2008/2008R2' = 'Version100'
                'SQLServer2012' = 'Version110'
                'SQLServer2014' = 'Version120'
                'SQLServer2016' = 'Version130'
            }

        $versionName = @{
                 'Version80' = 'SQLServer2000'
                 'Version90' = 'SQLServer2005'
                 'Version100' = 'SQLServer2008/2008R2'
                 'Version110' = 'SQLServer2012'
                 'Version120' = 'SQLServer2014'
                 'Version130' = 'SQLServer2016'
            }

	}
	PROCESS
	{
        # Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		$Exclude = $psboundparameters.Exclude

        if ($databases.Count -eq 0)
        {
            $databases = $sourceserver.Databases | Where-Object {$exclude -notcontains $_.Name -and $_.IsSystemObject -eq $false -and $_.IsAccessible -eq $true}
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
                $databases = $sourceserver.Databases | Where-Object {$exclude -notcontains $_.Name -and $_.IsSystemObject -eq $false -and $_.IsAccessible -eq $true -and ($databases -contains $_.Name)}
            }
        }

        if (@($databases).Count -gt 0)
        {

            #Database Permissions
            foreach ($db in $databases)
            {
                if ([string]::IsNullOrEmpty($DestinationVersion))
                {
                    #Get compatibility level for scripting the objects
                    $scriptVersion = $db.CompatibilityLevel
                }
                else
                {
                    $scriptVersion = $versions[$DestinationVersion]
                }

                #Options
                [Microsoft.SqlServer.Management.Smo.ScriptingOptions] $ScriptingOptions = New-Object "Microsoft.SqlServer.Management.Smo.ScriptingOptions";
                $ScriptingOptions.TargetServerVersion = [Microsoft.SqlServer.Management.Smo.SqlServerVersion]::$scriptVersion
                $ScriptingOptions.AllowSystemObjects = $false
                $ScriptingOptions.IncludeDatabaseRoleMemberships = $true
                $ScriptingOptions.ContinueScriptingOnError = $false;
                $ScriptingOptions.IncludeDatabaseContext = $false;

                Write-Output "Validating users on database '$($db.Name)'"

                if ($User.Count -eq 0)
                {
                    $Users = $db.Users | Where-Object {$_.IsSystemObject -eq $false -and $_.Name -notlike "##*"}
                }
                else
                {
                    if ($pipedatabase.Length -gt 0)
		            {
			            $Source = $pipedatabase[3].parent.name
			            $Users = $pipedatabase.name
		            }
                    else
                    {
                        $Users = $db.Users | Where-Object {$User -contains $_.Name -and $_.IsSystemObject -eq $false -and $_.Name -notlike "##*"}
                    }
                }
                   
                if ($Users.Count -gt 0)
                { 
                    foreach ($dbuser in $Users)
                    {
                        #setting database
                        $outsql += "USE [" + $db.Name + "]"

                        try
                        {
	                        #Fixed Roles #Dependency Issue. Create Role, before add to role.
                            foreach ($RolePermission in ($db.Roles | Where-Object {$_.IsFixedRole -eq $false}))
                            { 
                                foreach ($RolePermissionScript in $RolePermission.Script($ScriptingOptions))
                                {
                                    #$RoleScript = $RolePermission.Script($ScriptingOptions)
                                    $outsql += "$($RolePermissionScript.ToString())"
                                }
                            }

                            #Database Create User(s) and add to Role(s)
                            foreach ($dbUserPermissionScript in $dbuser.Script($ScriptingOptions))
                            {
                                if ($dbuserPermissionScript.Contains("sp_addrolemember"))
                                {
                                    $Execute = "EXEC "
                                } 
                                else 
                                {
                                    $Execute = ""
                                }
                                $outsql += "$Execute$($dbUserPermissionScript.ToString())"
                            }
                        
                            #Database Permissions
                            foreach ($DatabasePermission in $db.EnumDatabasePermissions() | Where-Object {@("sa","dbo","information_schema","sys") -notcontains $_.Grantee -and $_.Grantee -notlike "##*" -and ($dbuser.Name -contains $_.Grantee)})
                            {
                                if ($DatabasePermission.PermissionState -eq "GrantWithGrant")
                                {
                                    $WithGrant = "WITH GRANT OPTION"
                                } 
                                else 
                                {
                                    $WithGrant = ""
                                }
                                $GrantDatabasePermission = $DatabasePermission.PermissionState.ToString().Replace("WithGrant", "").ToUpper()

                                $outsql += "$($GrantDatabasePermission) $($DatabasePermission.PermissionType) TO [$($DatabasePermission.Grantee)] $WithGrant"
                            }


	                        #Database Object Permissions
                            foreach ($ObjectPermission in $db.EnumObjectPermissions() | Where-Object {@("sa","dbo","information_schema","sys") -notcontains $_.Grantee -and $_.Grantee -notlike "##*" -and $dbuser.Name -contains $_.Grantee})
                            {
                                switch ($ObjectPermission.ObjectClass)
				                {
					                "Schema" 
                                    { 
                                        $Object = "SCHEMA::[" + $ObjectPermission.ObjectName + "]" 
                                    }
					    
                                    "User" 
                                    { 
                                        $Object = "USER::[" + $ObjectPermission.ObjectName + "]" 
                                    }
                        
                                    default 
                                    { 
                                        $Object = "[" + $ObjectPermission.ObjectSchema + "].[" + $ObjectPermission.ObjectName + "]" 
                                    }
				                }

                                if ($ObjectPermission.PermissionState -eq "GrantWithGrant")
                                {
                                    $WithGrant = "WITH GRANT OPTION"
                        
                                } 
                                else 
                                {
                                    $WithGrant = ""
                                }
                                $GrantObjectPermission = $ObjectPermission.PermissionState.ToString().Replace("WithGrant","").ToUpper()

                                $outsql += "$GrantObjectPermission $($ObjectPermission.PermissionType) ON $Object TO [$($ObjectPermission.Grantee)] $WithGrant"
                            }

                        }
                        catch
                        {
                            Write-Warning "This user may be using functionality from $($versionName[$($db.CompatibilityLevel.ToString())]) that does not exist on the destination version ($DestinationVersion)."
                            Write-Exception $_
                        }
                    }
                }
                else
                {
                    Write-Output "No users found on database '$db'"
                }
                
                #reset collection
                $Users = $null
            }
        }
        else
        {
            Write-Output "No users found on instance '$sourceserver'"
        }
    }
	END
	{
        $sql = $outsql -join "`r`nGO`r`n"
        #add the final GO
        $sql += "`r`nGO"
		
		if ($FilePath.Length -gt 0)
		{
			$sql | Out-File -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
		}
		else
		{
			return $sql
		}
		
		If ($Pscmdlet.ShouldProcess("console", "Showing final message"))
		{
			Write-Output "--SQL User export to $FilePath complete"
			$sourceserver.ConnectionContext.Disconnect()
		}
	}
}
