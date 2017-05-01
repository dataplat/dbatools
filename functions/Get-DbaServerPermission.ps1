function Get-DbaServerPermission
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
        [switch]$Roles,
        [string]$SpecificLogin,
        [switch]$Detailed
	)
    begin
    {
        ## lazy dot source remove before merge request
        . C:\GitHub\dbatools\functions\Connect-dbaSqlServer.ps1
    }

    process
    {
       foreach ($Instance in $SqlInstance)
        {
            try
	        {
	            Write-Verbose "Connecting to $Instance"
                $server = Connect-SqlServer -SqlServer $Instance -SqlCredential $sqlcredential
	        }
	        catch
	        {
	            Write-Warning "Failed to connect to: $Instance"
                break
	        }
            
            if (-not $SpecificLogin)
            {
                Write-Verbose "No login supplied gathering all emails"
                $Logins = $server.Logins
            }
            else
            {
                Write-Verbose "Specific logins requeste"
               
                $Logins = $server.Logins | Where { $_.Name -contains $SpecificLogin }
                if ( -not $Logins)
                {
                write-warning "No Logins found matching : $SpecificLogin"
                break
                }
            }

            

            foreach ($Login in $Logins)
            { 
         
                if ($Login.ListMembers() -ne 0)
                {
                    write-verbose "Login is a memeber of groups"
                    foreach ($srvrole in $Login.ListMembers())
                    { 
                        $obj = [PSCustomObject]@{
                            ComputerName = $server.NetName
                            SqlInstance = $server.InstanceName
                            Login = $Login.Name
                            Role = $srvrole
                            PermissionState =  ""
                            PermissionsName =  ""
                        }
                        $obj   
                    }
                }
            }

            if (-not $Roles)
            {
                foreach ($serverperm in $server.EnumServerPermissions())
                {
                    if ( -not $SpecificLogin)
                    {
                        
                            $obj = [PSCustomObject]@{
                                    ComputerName = $server.NetName
                                    SqlInstance = $server.InstanceName
                                    Login = $serverperm.Grantee
                                    Role = ""
                                    PermissionState =  $serverperm.PermissionState
                                    PermissionsName =  $serverperm.PermissionType
                            }
                            $obj
                    }
                    else
                    {
                        if ($serverperm.Grantee -in $SpecificLogin)
                        {
                            $obj = [PSCustomObject]@{
                                    ComputerName = $server.NetName
                                    SqlInstance = $server.InstanceName
                                    Login = $serverperm.Grantee
                                    Role = ""
                                    PermissionState =  $serverperm.PermissionState
                                    PermissionsName =  $serverperm.PermissionType
                            }
                            $obj
                        }
                    }
                }
            }
        } # foreach
    } # process
}



