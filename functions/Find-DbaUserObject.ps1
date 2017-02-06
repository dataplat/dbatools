Function Find-DbaUserObject {
<#
.SYNOPSIS
Returns all stored procedures that contain the $value string passed in

.DESCRIPTION
This function can either run against specific databases or all user databases searching all user made stored procedures that contain a string ($Value).

.PARAMETER SqlServer
SQLServer name or SMO object representing the SQL Server to connect to. This can be a
collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, currend Windows login will be used.

.PARAMETER Database
Set the specific database/s that you wish to search in.

.PARAMETER Value
String value that you want to search for in the stored procedure textbody

.NOTES 
Original Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Get-DbaStoredProcedure

.EXAMPLE
Get-DbaStoredProcedure -SqlServer DEV01 -Value "html" -Verbose

Checks in all user databases stored procedures for "html" in the textbody

.EXAMPLE
Get-DbaStoredProcedure -SqlServer DEV01 -Database MyDB -Value "html" -Verbose

Checks in "mydb" database stored procedures for "html" in the textbody
#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[string[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[string[]]$Database,
        [parameter(Mandatory = $true)]
        [string]$Pattern
	)
	begin
    {
        #need to loop over certain objects multiple times so adding them here for simplificaiton
        $allJobs = $server.JobServer.Jobs 
    }

    process
    {
        Write-Verbose "Starting"
        foreach ($Instance in $SqlServer)
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
           

            <# Server objects  #> 
            ## Credentials
            if (-not $pattern)
            {
                write-verbose "Gather data on credentials"
                $creds = $server.Credentials 
                write-verbose "Gather data on proxy accounts"
                $proxys = $server.JobServer.ProxyAccounts
                write-verbose "Gather data on endpoints"
                $endPoints = $server.Endpoints|  Where {$_.Owner -ne "sa"}
                write-verbose "Gather data on Agent Jobs ownership"
                $jobs = $allJobs | Where {$_.OwnerLoginName  -ne "sa"}

            }
            else
            {
                write-verbose "Gather data on credentials"
                $creds = $server.Credentials | Where {$_.Identity -eq $pattern}
                write-verbose "Gather data on proxy accounts"
                $proxys = $server.JobServer.ProxyAccounts | Where {$_.CredentialIdentity -eq $Pattern} 
                write-verbose "Gather data on endpoints"
                $endPoints = $server.Endpoints|  Where {$_.Owner -eq $Pattern}
                write-verbose "Gather data on Agent Jobs ownership"
                $jobs = $allJobs | Where {$_.OwnerLoginName  -eq $Pattern}

            }
            
            if (-not $Database)
            {
                if (-not $Pattern)
                {
                    write-verbose "Gather data on database owners Note only checking online databases"
                    $Database = $server.Databases |  Where {$_.Status -eq "normal" -and $_.IsSystemObject -eq 0 -and $_.Owner -ne "sa"}
                }
                else
                {
                    write-verbose "Gather data on database owners Note only checking online databases"
                    $Database = $server.Databases |  Where {$_.Status -eq "normal" -and $_.IsSystemObject -eq 0 -and $_.Owner -eq $Pattern} ## not sure if this should be blank and just list them out no matter what
                }
            }
            else
            {
                if (-not $Pattern)
                {
                    write-verbose "Gather data on database owners Note only checking online databases"
                    $Database = $server.Databases |  Where {$_.Status -eq "normal" -and $_.IsSystemObject -eq 0 -and $_.Owner -ne "sa" -and $Database -contains $_.Name}
                }
                else
                {
                    write-verbose "Gather data on database owners Note only checking online databases"
                    $Database = $server.Databases |  Where {$_.Status -eq "normal" -and $_.IsSystemObject -eq 0 -and $_.Owner -eq $Pattern -and $Database -contains $_.Name}
                }
            }




            ## credentials
            foreach ($cred in $creds)
            {
                ## list credentials using the account
                
                $out = [PSCustomObject]@{
                    ComputerName = $server.NetName
                    SqlInstance = $server.InstanceName
		            ObjectType = "Credential" 
                    ObjectName = $cred.Name
                    ObjectDetails = $NULL
                }
                $out
            }
            
            ## proxys
            foreach ($proxy in $proxys)
            {
                $out = [PSCustomObject]@{
                ComputerName = $server.NetName
                SqlInstance = $server.InstanceName
		        ObjectType = "Proxy" 
                ObjectName = $proxy.Name
                ObjectDetails = $NULL
                }
                $out
            
                ## list agent jobs steps using proxy
                foreach ($job in $allJobs)
                {
                    foreach ($step in $job.JobSteps | Where {$_.ProxyName -eq $proxy.Name})
                    {
                        $out = [PSCustomObject]@{
                            ComputerName = $server.NetName
                            SqlInstance = $server.InstanceName
		                    ObjectType = "Agent Step" 
                            ObjectName = $job.Name
                            ObjectDetails = $step.Name
                        }
                        $out
                    }
                }
            }
            

            ## endpoints
            foreach ($endPoint in $endPoints)
            {
                $out = [PSCustomObject]@{
                    ComputerName = $server.NetName
                    SqlInstance = $server.InstanceName
		            ObjectType = "Endpoint" 
                    ObjectName = $endPoint.Name
                    ObjectDetails = $NULL
                }
                $out
            }

            ## agent jobs 
            foreach ($job in $jobs)
            {
                $out = [PSCustomObject]@{
                     ComputerName = $server.NetName
                    SqlInstance = $server.InstanceName
		            ObjectType = "Agent Job" 
                    ObjectName = $job.Name
                    ObjectDetails = $NULL
                }
                $out
            }

            ## db owned by pattern
             if (-not $Database)
            {
                
            }
            
            foreach ($db in $dbs)
            {
                $dbName = $db.Name
                $d = $server.Databases.Item($dbName)
                
                $out = [PSCustomObject]@{
                    ComputerName = $server.NetName
                    SqlInstance = $server.InstanceName
		            Database =$dbName
                    Object = $NULL
                    ObjectType = $NULL 
                }
                $out 
            }
        }
    }
}