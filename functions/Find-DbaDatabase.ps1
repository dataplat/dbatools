function Find-DbaDatabase
{
<#
.SYNOPSIS
Find database/s on multiple servers that match critea you input

.DESCRIPTION
Allows you to search Sql Instances for database that have either the same name or service broker guid. You can use the like operator for database name, but this cannot be used in the service broker search.
There a several reasons for the service broker guid not matching on a restored database primarily using alter database new broker. or turn off broker to return a guid of 0000-0000-0000-0000. 

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Type
What sort of search would like to complete. Either Service Broker GUID or Database name. 

.PARAMETER Name
Value that is searched for

.PARAMETER Like
Allows you to search database name using *<NAME>*

.PARAMETER Detailed
Output a more detailed view showing ComputerName, SqlInstance, Database, ServiceBrokerGUID, Tables, StoredProcedures,Views and ExtendedProperties to see they closely match to help find related databases.

.NOTES
Author: Stephen Bennett: https://sqlnotesfromtheunderground.wordpress.com/

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Find-DbaDatabase

.EXAMPLE
Find-DbaDatabase -SqlInstance "DEV01", "DEV02", "UAT01", "UAT02", "PROD01", "PROD02" -Type Database -Name TestDB -Detailed 
Returns all database from the SqlInstances that have a database named TestDB with a detailed output.

.EXAMPLE
Find-DbaDatabase -SqlInstance "DEV01", "DEV02", "UAT01", "UAT02", "PROD01", "PROD02" -Type Service_Broker_GUID -Name 25b64fef-faeb-495a-9898-f25a782835f5 -Detailed 
Returns all database from the SqlInstances that have the same Service Broker GUID with a deeatiled output

#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias('cn','host','computer','server')]
		[string[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
        [parameter(Mandatory = $true)]
        [ValidateSet('Database','Service_Broker_GUID')]
        [string]$Type,
        [parameter(Mandatory = $true)]
        [string]$Name,
        [switch]$Like,
        [switch]$Detailed
	)
    process
    {
        foreach ($Instance in $SqlInstance)
        {
            try
	        {
	            Write-Verbose "Connecting to $Instance"
                $srv = Connect-SqlServer -SqlServer $Instance -SqlCredential $sqlcredential
	        }
	        catch
	        {
	            Write-Warning "Failed to connect to: $srv"
                break
	        }

            if($srv -contains "\")
            {
                $computername = ($srv.Name).Split("\")[0]
                $inst =  ($srv.Name).Split("\")[1]
            }
            else
            {
                $computername = $srv.Name
                $inst =  ""
            }

        if ($Type -eq 'Database')
        {
            if ($Like)
            {
                $match = $srv.Databases | Where-Object {$_.Name -like "*$name*"}
            }
            else
            {
                $match = $srv.Databases | Where-Object {$_.Name -eq $name}
            }
            foreach ($db in $match)
            {
                if ($Detailed)
                {
                    if ($db.ExtendedProperties.Count -ne 0)
                    {
                        $outep = @()
                        foreach ($xp in $db.ExtendedProperties) 
                        {
                            $extdetails = [PSCustomObject]@{
		                       Name = $db.ExtendedProperties[$xp.Name].Name
		                       Value = $db.ExtendedProperties[$xp.Name].Value
                                }
                            $outep += $extdetails
                        }
                    }
                    else
                    {
                        $outep = ""
                    }
                    $out = [PSCustomObject]@{
		                ComputerName = $computername
                        SqlInstance = $inst
		                Database = $db.Name
                        ServiceBrokerGuid = $db.ServiceBrokerGuid
                        Tables = ($db.Tables | where {$_.IsSystemObject -eq 0}).Count
                        StoredProcedures = ($db.StoredProcedures | where {$_.IsSystemObject -eq 0}).Count
                        Views = ($db.Views | where {$_.IsSystemObject -eq 0}).Count
                        ExtendedPropteries = $outep
                        }
                    $out
                }
                else 
                {
                    $out = [PSCustomObject]@{
		                ComputerName = $computername
                        SqlInstance = $inst
		                Database = $db.Name
                        }
                    $out
                }
            }     
        }
        else
        {
            if ($Like)
            {
                write-warning "You cannot use the LIKE functionality with ServiceBrokerGUID as the Type"
                break
            }
            else
            {
                $match = $srv.Databases | Where-Object {$_.ServiceBrokerGuid -eq $name}
            }
            foreach ($db in $match)
            {

                if ($Detailed)
                {
                    if ($db.ExtendedProperties.Count -ne 0)
                    {
                        $outep = @()
                        foreach ($xp in $db.ExtendedProperties) 
                        {
                            $extdetails = [PSCustomObject]@{
		                       Name = $db.ExtendedProperties[$xp.Name].Name
		                       Value = $db.ExtendedProperties[$xp.Name].Value
                                }
                            $outep += $extdetails
                        }
                    }
                    else
                    {
                        $outep = ""
                    }
                        $out = [PSCustomObject]@{
		                    ComputerName = $computername
                            SqlInstance = $inst 
		                    Database = $db.Name
                            ServiceBrokerGuid = $db.ServiceBrokerGuid
                            Tables = ($db.Tables | where {$_.IsSystemObject -eq 0}).Count
                            StoredProcedures = ($db.StoredProcedures | where {$_.IsSystemObject -eq 0}).Count
                            Views = ($db.Views | where {$_.IsSystemObject -eq 0}).Count
                            ExtendedPropteries = $outep
                            }
                        $out
                }
                else 
                {
                    $out = [PSCustomObject]@{
		                ComputerName = $computername
                        SqlInstance = $inst
		                Database = $db.Name
                        }
                    $out
                    }
                }
            }
        }
    }
}
