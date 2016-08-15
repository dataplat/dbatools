function Set-DbaJobOwner {
<#
.SYNOPSIS
Sets SQL Agent job owners with a desired login if jobs do not match that owner.

.DESCRIPTION
This function will alter SQL Agent Job ownership to match a specified login if their
current owner does not match the target login. By default, the target login will
be 'sa', but the fuction will allow the user to specify a different login for 
ownership. The user can also apply this to all jobs or only to a select list
of jobs (passed as either a comma separated list or a string array).

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

.PARAMETER Jobs
List of Jobs to apply changes to. Will accept a comma separated list or a string array.

.PARAMETER TargetLogin
Specific login that you wish to check for ownership. This defaults to 'sa'.

.LINK
https://dbatools.io/Set-DbaJobOwner

.EXAMPLE
Set-DbaJobOwner -SqlServer localhost

Sets SQL Agent Job owner to 'sa' on all jobs where the owner does not match 'sa'.

.EXAMPLE
Set-DbaJobOwner -SqlServer localhost -TargetLogin 'DOMAIN\account'

Sets SQL Agent Job owner to sa on all jobs where the owner does not match 'DOMAIN\account'. Note
that TargetLogin must be a valid security principal that exists on the target server.

.EXAMPLE
Set-DbaJobOwner -SqlServer localhost -Databases 'junk,dummy'

Sets SQL Agent Job owner to 'sa' on the junk and dummy jobs if their current owner does not match 'sa'.
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
        [object[]]$Jobs,
        [string]$TargetLogin = 'sa'
	)

    BEGIN{
        #connect to the instance
		Write-Verbose "Connecting to $SqlServer"
		$server = Connect-SqlServer $SqlServer -SqlCredential $SqlCredential
        
        #Validate login
        if(($server.Logins.Name) -notcontains $TargetLogin){
            throw "Invalid login: $TargetLogin"
            return $null
        }
    }
    PROCESS{
        #Get database list. If value for -Jobs is passed, massage to make it a string array.
        #Otherwise, use all jobs on the instance where owner not equal to -TargetLogin
        Write-Verbose "Gathering jobs to update"
        if($Jobs){
            $check = (($Jobs -join ',') -split ',')
            $jobcollection = $server.JobServer.Jobs | Where-Object {$_.OwnerLoginName -ne $TargetLogin -and $check -contains $_.Name }
        } else { 
            $jobcollection = $server.JobServer.Jobs | Where-Object {$_.OwnerLoginName -ne $TargetLogin}
        }

        Write-Verbose "Updating $($jobcollection.Count) job(s)."
        foreach($j in $jobcollection){
            If($PSCmdlet.ShouldProcess($j,"Setting job owner to $TargetLogin")){
                try{
                    #Set job owner to $TargetLogin (default 'sa')
                    $j.OwnerLoginName = $TargetLogin
                    $j.Alter()
                } catch {
                    # write-exception writes the full exception to file
					Write-Exception $_
					throw $_
                }
            }
        }
    }
    END{
        Write-Verbose "Closing connection"
        $server.ConnectionContext.Disconnect()
    }
}