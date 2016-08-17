function Test-DbaDatabaseOwner {
<#
.SYNOPSIS
Checks database owners against a login to validate which databases do not match that owner.

.DESCRIPTION
This function will check all databases on an instance against a SQL login to validate if that
login owns those databases or not. By default, the function will check against 'sa' for 
ownership, but the user can pass a specific login if they use something else. Only databases
that do not match this ownership will be displayed, but if the -Detailed switch is set all
databases will be shown.

Best Practice reference: http://weblogs.sqlteam.com/dang/archive/2008/01/13/Database-Owner-Troubles.aspx
	
.NOTES 
Original Author: Michael Fal (@Mike_Fal), http://mikefal.net

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.PARAMETER SqlServer
SQLServer name or SMO object representing the SQL Server to connect to. This can be a
collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect under. If not specified, currend Windows login will be used.

.PARAMETER TargetLogin
Specific login that you wish to check for ownership. This defaults to 'sa'.

.PARAMETER Detailed
Switch parameter. When declared, function will return all databases and whether or not they
match the declared owner.

.LINK
https://dbatools.io/Test-DbaDatabaseOwner

.EXAMPLE
Test-DbaDatabaseOwner -SqlServer localhost

Returns all databases where the owner does not match 'sa'.

.EXAMPLE
Test-DbaDatabaseOwner -SqlServer localhost -TargetLogin 'DOMAIN\account'

Returns all databases where the owner does not match 'DOMAIN\account'. Note
that TargetLogin must be a valid security principal that exists on the target server.
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
        [string]$TargetLogin = 'sa',
        [Switch]$Detailed
	)

    BEGIN{
        #connect to the instance and set return array empty
        $return = @()
		Write-Verbose "Connecting to $SqlServer"
		$server = Connect-SqlServer $SqlServer -SqlCredential $SqlCredential
        
        #Validate login
        if(($server.Logins.Name) -notcontains $TargetLogin){
            throw "Invalid login: $TargetLogin"
            return $null
        }
    }
    PROCESS{
        #for each database, create custom object for return set.
        foreach($db in ($server.Databases)){
            Write-Verbose "Checking $db"
            $row = [ordered]@{ `
                        'Database'=$db.Name; `
                        'CurrentOwner'=$db.Owner; `
                        'TargetOwner'=$TargetLogin; `
                        'OwnerMatch'=($db.owner -eq $TargetLogin); `
                        }
            #add each custom object to the return array
            $return += New-Object PSObject -Property $row
        }

    }
    END{
        #return results
        if($Detailed){
            Write-Verbose "Returning detailed results."
            return $return
        } else {
            Write-Verbose "Returning default results."
            return ($return | Where-Object {$_.OwnerMatch -eq $false})
        }
    }

}