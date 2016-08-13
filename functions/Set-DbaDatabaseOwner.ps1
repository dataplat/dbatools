function Set-DbaDatabaseOwner {
<#
.SYNOPSIS
Sets database owners with a desired login if databases do not match that owner.

.DESCRIPTION
This function will alter database ownershipt to match a specified login if their
current owner does not match the target login. By default, the target login will
be 'sa', but the fuction will allow the user to specify a different login for 
ownership. The user can also apply this to all databases or only to a select list
of databases (passed as either a comma separated list or a string array).

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

.PARAMETER Datbases
List of databases to apply changes to. Will accept a comma separated list or a string array.

.PARAMETER TargetLogin
Specific login that you wish to check for ownership. This defaults to 'sa'.

.LINK
https://dbatools.io/Set-DbaDatabaseOwner

.EXAMPLE
Set-DbaDatabaseOwner -SqlServer localhost

Sets database owner to 'sa' on all databases where the owner does not match 'sa'.

.EXAMPLE
Set-DbaDatabaseOwner -SqlServer localhost -TargetLogin 'DOMAIN\account'

Sets database owner to sa on all databases where the owner does not match 'DOMAIN\account'. Note
that TargetLogin must be a valid security principal that exists on the target server.

.EXAMPLE
Set-DbaDatabaseOwner -SqlServer localhost -Databases 'junk,dummy'

Sets database owner to 'sa' on the junk and dummy databases if their current owner does not match 'sa'.
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
        [object[]]$Databases,
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
        #Get database list. If value for -Databases is passed, massage to make it a string array.
        #Otherwise, use all databases on the instance where owner not equal to -TargetLogin
        Write-Verbose "Gathering databases to update"
        if($Databases){
            $check = (($databases -join ',') -split ',')
            $dbs = $server.Databases | Where-Object {$_.Owner -ne $TargetLogin -and $check -contains $_.Name }
        } else { 
            $dbs = $server.Databases | Where-Object {$_.Owner -ne $TargetLogin}
        }

        Write-Verbose "Updating $($dbs.Count) database(s)."
        foreach($db in $dbs){
            If($PSCmdlet.ShouldProcess($db,"Setting database owner to $TargetLogin")){
                try{
                    #Set database owner to $TargetLogin (default 'sa')
                    $db.SetOwner($TargetLogin)
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