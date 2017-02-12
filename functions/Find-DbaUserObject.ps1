Function Find-DbaUserObject {
<#
.SYNOPSIS
Loops over multiple SMO objects to find objects owned by users. or for any object owned by a specific user using the -Pattern parameter

.DESCRIPTION
Looks at the below list of objects to see if they are either owned by a user or a specific user (using the parameter -Pattern)
    Database Owner
    Agent Job Owner
    Used in Credential
    USed in Proxy
    SQL Agent Steps using a Proxy
    Endpoints
    Database Schemas
    Database Roles
    Dabtabase Assembles
    Database Synonyms

.PARAMETER SqlServer
SQLServer name or SMO object representing the SQL Server to connect to. This can be a
collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, currend Windows login will be used.

.PARAMETER Patterm
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
        [string]$Pattern
	)
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
           
            ## Credentials
            if (-not $pattern)
            {
                write-verbose "Gather data on credentials"
                $creds = $server.Credentials 
                write-verbose "Gather data on proxy accounts"
                $proxys = $server.JobServer.ProxyAccounts
                write-verbose "Gather data on endpoints"
                $endPoints = $server.Endpoints|  Where-Object {$_.Owner -ne "sa"}
                write-verbose "Gather data on Agent Jobs ownership"
                $jobs = $allJobs | Where-Object {$_.OwnerLoginName  -ne "sa"}
            }
            else
            {
                write-verbose "Gather data on credentials"
                $creds = $server.Credentials | Where-Object {$_.Identity -eq $pattern}
                write-verbose "Gather data on proxy accounts"
                $proxys = $server.JobServer.ProxyAccounts | Where-Object {$_.CredentialIdentity -eq $Pattern} 
                write-verbose "Gather data on endpoints"
                $endPoints = $server.Endpoints|  Where-Object {$_.Owner -eq $Pattern}
                write-verbose "Gather data on Agent Jobs ownership"
                $jobs = $allJobs | Where-Object {$_.OwnerLoginName  -eq $Pattern}
            }
            
             
            ## dbs
            if (-not $Pattern)
            {
                foreach ($db in $server.Databases | Where-Object{$_.Owner -ne "sa"})
                {
                    write-verbose "checking if $db is owned "
                    $d = $server.Databases.Item("$db")
                    $out = [PSCustomObject]@{
                        ComputerName = $server.NetName
                        SqlInstance = $server.InstanceName
		                ObjectType = "Database" 
                        ObjectOwner = $db.Owner
                        ObjectName = $db.Name
                        ObjectDetails = $NULL
                    }
                    $out 
                }
            }
            else
            {
                foreach ($db in $server.Databases | Where-Object {$_.Owner -eq $Pattern})
                {

                    $d = $server.Databases.Item("$db")
                    $out = [PSCustomObject]@{
                        ComputerName = $server.NetName
                        SqlInstance = $server.InstanceName
		                ObjectType = "Database" 
                        ObjectOwner = $db.Owner
                        ObjectName = $db.Name
                        ObjectDetails = $NULL
                    }
                    $out 
                }          
            
            }      

            ## agent jobs 
            if (-not $Pattern)
            {
                foreach ($job in $server.JobServer.Jobs | Where-Object {$_.OwnerLoginName -ne "sa"})
                {
                    $out = [PSCustomObject]@{
                        ComputerName = $server.NetName
                        SqlInstance = $server.InstanceName
                        ObjectType = "Agent Job" 
                        ObjectOwner = $job.OwnerLoginName
                        ObjectName = $job.Name
                        ObjectDetails = $NULL
                    }
                    $out
                }
            }
            else
            {
                foreach ($job in $server.JobServer.Jobs | Where-Object {$_.OwnerLoginName -eq $Pattern})
                {
                    $out = [PSCustomObject]@{
                        ComputerName = $server.NetName
                        SqlInstance = $server.InstanceName
                        ObjectType = "Agent Job" 
                        ObjectOwner = $job.OwnerLoginName
                        ObjectName = $job.Name
                        ObjectDetails = $NULL
                    }
                    $out
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
                    ObjectOwner = $cred.Identity
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
                ObjectOwner = $proxy.CredentialIdentity
                ObjectName = $proxy.Name
                ObjectDetails = $NULL
                }
                $out
            
                ## list agent jobs steps using proxy
                foreach ($job in $server.JobServer.Jobs)
                {
                    foreach ($step in $job.JobSteps | Where-Object {$_.ProxyName -eq $proxy.Name})
                    {
                        $out = [PSCustomObject]@{
                            ComputerName = $server.NetName
                            SqlInstance = $server.InstanceName
		                    ObjectType = "Agent Step" 
                            ObjectOwner = $step.ProxyName
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
                    ObjectOwner = $endpoint.Owner
                    ObjectName = $endPoint.Name
                    ObjectDetails = $NULL
                }
                $out
            }

            ## Loop internal database
            foreach ($db in $server.Databases | Where-Object {$_.Status -eq "Normal"})
            {
                Write-Verbose "Gather user owned object in database: $db"
                ##schemas
                $sysSchemas = "DatabaseMailUserRole", "db_ssisadmin", "db_ssisltduser", "db_ssisoperator", "SQLAgentOperatorRole", "SQLAgentReaderRole", "SQLAgentUserRole", "TargetServersRole", "RSExecRole"

                if (-not $Pattern)
                {
                    $schs = $db.Schemas | Where-Object {$_.IsSystemObject -eq 0 -and $_.Owner -ne "dbo"  -and $sysSchemas -notcontains $_.Owner}
                }
                else
                {
                   $schs = $db.Schemas | Where-Object {$_.IsSystemObject -eq 0 -and $_.Owner -eq $Pattern  -and $sysSchemas -notcontains $_.Owner} 
                }
                foreach ($sch in $schs)
                {
                    $out = [PSCustomObject]@{
                        ComputerName = $server.NetName
                        SqlInstance = $server.InstanceName
		                ObjectType = "Schema" 
                        ObjectOwner = $sch.Owner
                        ObjectName = $sch.Name
                        ObjectDetails = $db.Name
                        }
                        $out
                }

                ## database roles
                if (-not $Pattern)
                {
                    $roles = $db.Roles | Where-Object {$_.IsSystemObject -eq 0 -and $_.Owner -ne "dbo"}
                }
                else
                {
                    $roles = $db.Roles | Where-Object {$_.IsSystemObject -eq 0 -and $_.Owner -eq $Pattern}
                }
                foreach ($role in $roles)
                {
                    $out = [PSCustomObject]@{
                        ComputerName = $server.NetName
                        SqlInstance = $server.InstanceName
		                ObjectType = "Database Role" 
                        ObjectOwner = $role.Owner
                        ObjectName = $role.Name
                        ObjectDetails = $db.Name
                        }
                        $out
                }

                ## assembly
                if (-not $Pattern)
                {             
                    $Assemblies = $db.Assemblies | Where-Object {$_.IsSystemObject -eq 0 -and $_.Owner -ne "dbo"}
                }
                else
                {
                    $Assemblies = $db.Assemblies | Where-Object {$_.IsSystemObject -eq 0 -and $_.Owner -eq $Pattern}
                }
                foreach ($Assemblie in $Assemblies)
                {
                    $out = [PSCustomObject]@{
                        ComputerName = $server.NetName
                        SqlInstance = $server.InstanceName
		                ObjectType = "Database Assembly" 
                        ObjectOwner = $Assemblie.Owner
                        ObjectName = $Assemblie.Name
                        ObjectDetails = $db.Name
                        }
                        $out
                }

              ## synonyms
                if (-not $Pattern)
                {             
                    $Synonymss = $db.Synonyms | Where-Object {$_.IsSystemObject -eq 0 -and $_.Owner -ne "dbo"}
                }
                else
                {
                    $Synonymss = $db.Synonyms | Where-Object {$_.IsSystemObject -eq 0 -and $_.Owner -eq $Pattern}
                }
                foreach ($Synonyms in $Synonymss)
                {
                    $out = [PSCustomObject]@{
                        ComputerName = $server.NetName
                        SqlInstance = $server.InstanceName
		                ObjectType = "Database Synonyms" 
                        ObjectOwner = $Synonyms.Owner
                        ObjectName = $Synonyms.Name
                        ObjectDetails = $db.Name
                        }
                        $out
                }
            }  

        }
    }
}