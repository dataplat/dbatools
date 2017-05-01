function Get-DbaDatabasePermission
{
<#
.SYNOPSIS
Get a list of Database level permissions

.DESCRIPTION
Retrieves information on either selected databases or all databases showing roles and object level permissions.

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Databases
Return information for only specific databases

.NOTES
Author: Stephen Bennett ( https://sqlnotesfromtheunderground.wordpress.com/ )
	
dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

	
.LINK
https://dbatools.io/Get-DbaDatabasePermisson

.EXAMPLE
Get-DbaDatabasePermisson -SqlServer DEV01 -Database Avatar

Returns all user permissions including the role and object level permissions

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[string[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[string[]]$Databases,
        [switch]$Roles,
        [string[]]$Logins
	)
    PROCESS
    {
       foreach ($Instance in $SqlInstance)
        {
            try
	        {
	            Write-Verbose "Connecting to $Instance"
                $server = Connect-DbaSqlServer -SqlServer $Instance -SqlCredential $sqlcredential
	        }
	        catch
	        {
	            Write-Warning "Failed to connect to: $Instance"
                break
	        }

            
            if (-not $Databases)
            {
                Write-Verbose "No databases selected"
                $Dbs = $server.Databases | Where { $_.IsSystemObject -eq 0 -and $_.Status -eq "normal" } | select name
            }
            else
            {
                Write-Verbose "Looking for specifc databases"
                $Dbs = $server.Databases | Where { $_.IsSystemObject -eq 0 -and $_.Status -eq "normal" -and $Databases -contains $_.name } | select name
            }
            
            foreach ($database in $Dbs)
            {
                    $dbname = $database.Name        
                try
                {

                    $db = $server.Databases["$dbname"]
                }
                catch
                {
                    Write-Warning "Failed to connect to Database: $db"
                    break
                }

                if (-not $Logins)
                {
                    $users = $db.Users
                }
                else
                {
                   $users = $db.Users | Where {$_.Name -contains $Logins} 
                }

                foreach ($user in $users)
                {
                    Write-Verbose "User: $user"
                    foreach ($role in $user.EnumRoles())
                    {
                        $obj = [PSCustomObject]@{
                            ComputerName = $server.NetName
                            SqlInstance = $server.InstanceName
                            Database = $db.Name
                            Login = $user.Name
                            Role = $role
                            Object =  "Database"
                            PermissionState =  ""
                            PermissionsName =  ""
                        }
                        $obj
                    }
                    
                    if (-not $Roles)
                    {
                        foreach($dbPer in $db.EnumDatabasePermissions($user.Name))
                        {
                            $obj = [PSCustomObject]@{
                                ComputerName = $server.NetName
                                SqlInstance = $server.InstanceName
                                Database = $db.Name
                                Login = $user.Name
                                Role = ""
                                Object = "Database"
                                PermissionState = $dbPer.PermissionState
                                PermissionsName = $dbPer.PermissionType  
                            }
                            $obj
                        }
                        foreach($objPerm in $db.EnumObjectPermissions($user.Name))
                        {
                            $obj = [PSCustomObject]@{
                                ComputerName = $server.NetName
                                SqlInstance = $server.InstanceName
                                Database = $db.Name
                                Login = $user.Name
                                Role =  ""
                                Object =  $objPerm.ObjectSchema + "." + $objPerm.ObjectName
                                PermissionState = $objPerm.PermissionState
                                PermissionsName = $objPerm.PermissionType
                            }
                            $obj
                        }
   
                    } # end not role
                } # foreach user 
                
                if (-not $Roles)
                {
                    $customRoles = $db.Roles | Where { $_.IsFixedRole -eq $False -and $_.name -ne "Public" } 
                    
                    foreach ($customRole in $customRoles)
                    {
                        foreach ($rp in $db.EnumDatabasePermissions($customRole.Name))
                        {
                            $obj = [PSCustomObject]@{
                                ComputerName = $server.NetName
                                SqlInstance = $server.InstanceName
                                Database = $db.Name
                                Role = $customRole.Name
                                Object =  "Database"
                                PermissionState =  $rp.PermissionState
                                PermissionsName =  $rp.PermissionType
                                }
                            $obj    
                        }   
                    }
                }
            } # foreach db 
        } # sql instance loop
    } # process
} # function 