function Find-DbaLoginInGroup
{
<#
.SYNOPSIS
Finds Logins in Active Directory groups. 

.DESCRIPTION
Outputs all the active directory groups 
	
.NOTES 
Original Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.PARAMETER SqlServer
SQLServer name or SMO object representing the SQL Server to connect to. This can be a
collection and recieve pipeline input.

.PARAMETER SqlCredential
PSCredential object to connect under. If not specified, currend Windows login will be used.

.PARAMETER Login
Find all AD Groups used on the instance that an individual login is a memeber of.
	
.LINK
https://dbatools.io/Find-DbaLoginInGroup

.EXAMPLE
Find-DbaLoginInGroup -SqlInstance DEV01 -Login "MyDomain\Stephen.Bennett"

Returns all active directory groups with logins on Sql Instance DEV01 that contain the AD user Stephen.Bennett.

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[string[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
        [string]$Login
	)
    begin
    {
        try
        {
            Add-Type -AssemblyName  System.DirectoryServices.AccountManagement;
        }
        catch
        {
            Write-warning "Failed to load Assembly needed" 
            break
        }
    }
    
    PROCESS
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
                continue
	        }

            $AdGroups = $server.Logins | Where {$_.LoginType -eq "WindowsGroup" -and $_.Name -ne "BUILTIN\Administrators" -and $_.Name -notlike "*NT SERVICE*"}
            $ADGroupOut = @()
            foreach ($AdGroup in $AdGroups)
            {
                try 
                {
                    $domain = $AdGroup.Name.Split("\")[0]
                    $ads = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain', $domain) 
                    [string] $groupName = $AdGroup.Name
                    $group = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($ads, $groupName); 
                    foreach ($member in $group.Members)
                    {
                        $adout = [PSCustomObject]@{
		                    GroupName = $AdGroup.Name
                            Login = $member.SamAccountName
                            }
		                $ADGroupOut += $adout
                    } 
                }
                catch
                {
                    write-warning "error connecting to $AdGroup, run Test-DbaValidLogin to ensure the group exist in AD"
                }
            }

            Foreach ($l in $Login)
            {
                $username = $l.Split("\")[1]
                write-verbose "Looking for $username"
                $FoundYou = @()
                try 
                {    
                    $FoundYou = $ADGroupOut | Where {$_.Login -eq $username} 
         
                }
                catch
                {
                    write-warning "Failed to find Login: $Login as a Login or in a group connecting to server: $server"
                    break
                }

                foreach($gf in $FoundYou)
                {
                
                    $gfRole = $gf.GroupName
                    $output = [PSCustomObject]@{
                        ComputerName = $server.NetName
                        SqlInstance = $server.InstanceName
                        Login = $l
                        Member = $gfRole
                    }
                    Select-DefaultField -InputObject $output -Property ComputerName, SqlInstance, Login, Member  
                }
            } 
        } 
    }
}