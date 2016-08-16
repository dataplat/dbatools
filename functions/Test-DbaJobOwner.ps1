function Test-DbaJobOwner {
<#
.SYNOPSIS
Checks SQL Agent Job owners against a login to validate which jobs do not match that owner.

.DESCRIPTION
This function will check all SQL Agent Job on an instance against a SQL login to validate if that
login owns those SQL Agent Jobs or not. By default, the function will check against 'sa' for 
ownership, but the user can pass a specific login if they use something else. Only SQL Agent Jobs
that do not match this ownership will be displayed, but if the -Detailed switch is set all
SQL Agent Jobs will be shown.

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


.LINK
https://dbatools.io/Test-DbaJobOwner

.EXAMPLE
Test-DbaJobOwner -SqlServer localhost

Returns all databases where the owner does not match 'sa'.

.EXAMPLE
Test-DbaJobOwner -SqlServer localhost -TargetLogin 'DOMAIN\account'

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
        if($server.Logins.Name -notcontains $TargetLogin){
            throw "Invalid login: $TargetLogin"
            return $null
        }

        if($server.logins[$TargetLogin].LoginType -eq 'WindowsGroup'){
            throw "$TargetLogin is a Windows Group and can not be a job owner."
            return $null
        }
    }
    PROCESS{
        #for each database, create custom object for return set.
        foreach($job in ($server.JobServer.Jobs)){
            Write-Verbose "Checking $job"
            $row = [ordered]@{ `
                        'Job'=$job.Name; `
                        'CurrentOwner'=$job.OwnerLoginName; `
                        'TargetOwner'=$TargetLogin; `
                        'OwnerMatch'=($job.OwnerLoginName -eq $TargetLogin); `
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