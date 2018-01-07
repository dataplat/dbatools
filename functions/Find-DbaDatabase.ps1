function Find-DbaDatabase {
    <#
.SYNOPSIS
Find database/s on multiple servers that match criteria you input

.DESCRIPTION
Allows you to search SQL Server instances for database that have either the same name, owner or service broker guid.

There a several reasons for the service broker guid not matching on a restored database primarily using alter database new broker. or turn off broker to return a guid of 0000-0000-0000-0000.

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Property
What you would like to search on. Either Database Name, Owner, or Service Broker GUID. Database name is the default.

.PARAMETER Pattern
Value that is searched for. This is a regular expression match but you can just use a plain ol string like 'dbareports'

.PARAMETER Exact
Search for an exact match instead of a pattern

.PARAMETER Detailed
Output all properties, will be depreciated in 1.0.0 release.

.PARAMETER EnableException
By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: DisasterRecovery
Author: Stephen Bennett: https://sqlnotesfromtheunderground.wordpress.com/

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
 https://dbatools.io/Find-DbaDatabase

.EXAMPLE
Find-DbaDatabase -SqlInstance "DEV01", "DEV02", "UAT01", "UAT02", "PROD01", "PROD02" -Pattern Report
Returns all database from the SqlInstances that have a database with Report in the name

.EXAMPLE
Find-DbaDatabase -SqlInstance "DEV01", "DEV02", "UAT01", "UAT02", "PROD01", "PROD02" -Pattern TestDB -Exact | Select-Object *
Returns all database from the SqlInstances that have a database named TestDB with a detailed output.

.EXAMPLE
Find-DbaDatabase -SqlInstance "DEV01", "DEV02", "UAT01", "UAT02", "PROD01", "PROD02" -Property ServiceBrokerGuid -Pattern '-faeb-495a-9898-f25a782835f5' | Select-Object *
Returns all database from the SqlInstances that have the same Service Broker GUID with a deatiled output

#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [ValidateSet('Name', 'ServiceBrokerGuid', 'Owner')]
        [string]$Property = 'Name',
        [parameter(Mandatory = $true)]
        [string]$Pattern,
        [switch]$Exact,
        [switch]$Detailed,
        [switch][Alias('Silent')]$EnableException
    )
    begin {
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter Detailed
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Verbose "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Write-Warning "Failed to connect to: $instance"
                continue
            }

            if ($exact -eq $true) {
                $dbs = $server.Databases | Where-Object IsAccessible | Where-Object { $_.$property -eq $pattern }
            }
            else {
                try {
                    $dbs = $server.Databases | Where-Object IsAccessible | Where-Object { $_.$property.ToString() -match $pattern }
                }
                catch {
                    # they probably put asterisks thinking it's a like
                    $Pattern = $Pattern -replace '\*', ''
                    $Pattern = $Pattern -replace '\%', ''
                    $dbs = $server.Databases | Where-Object { $_.$property.ToString() -match $pattern }
                }
            }

            foreach ($db in $dbs) {

                $extendedproperties = @()
                foreach ($xp in $db.ExtendedProperties) {
                    $extendedproperties += [PSCustomObject]@{
                        Name  = $db.ExtendedProperties[$xp.Name].Name
                        Value = $db.ExtendedProperties[$xp.Name].Value
                    }
                }

                if ($extendedproperties.count -eq 0) { $extendedproperties = 0 }

                [PSCustomObject]@{
                    ComputerName       = $server.NetName
                    InstanceName       = $server.ServiceName
                    SqlInstance        = $server.Name
                    Name               = $db.Name
                    SizeMB             = $db.Size
                    Owner              = $db.Owner
                    CreateDate         = $db.CreateDate
                    ServiceBrokerGuid  = $db.ServiceBrokerGuid
                    Tables             = ($db.Tables | Where-Object { $_.IsSystemObject -eq $false }).Count
                    StoredProcedures   = ($db.StoredProcedures | Where-Object { $_.IsSystemObject -eq $false }).Count
                    Views              = ($db.Views | Where-Object { $_.IsSystemObject -eq $false }).Count
                    ExtendedProperties = $extendedproperties
                    Database           = $db
                } | Select-DefaultView -ExcludeProperty Database, ExtendedProperties, ServiceBrokerGuid, StoredProcedures, Tables, Views
            }
        }
    }
}
