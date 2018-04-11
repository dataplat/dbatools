function Get-DbaDatabaseUdf {
    <#
.SYNOPSIS
Gets database User Defined Functions

.DESCRIPTION
Gets database User Defined Functions

.PARAMETER SqlInstance
The target SQL Server instance(s)

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials

.PARAMETER Database
To get User Defined Functions from specific database(s)

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto populated from the server

.PARAMETER ExcludeSystemUdf
This switch removes all system objects from the UDF collection

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: security, Databases
Author: Klaas Vandenberghe ( @PowerDbaKlaas )

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.EXAMPLE
Get-DbaDatabaseUdf -SqlInstance sql2016

Gets all database User Defined Functions

.EXAMPLE
Get-DbaDatabaseUdf -SqlInstance Server1 -Database db1

Gets the User Defined Functions for the db1 database

.EXAMPLE
Get-DbaDatabaseUdf -SqlInstance Server1 -ExcludeDatabase db1

Gets the User Defined Functions for all databases except db1

.EXAMPLE
Get-DbaDatabaseUdf -SqlInstance Server1 -ExcludeSystemUdf

Gets the User Defined Functions for all databases that are not system objects (there can be 100+ system User Defined Functions in each DB)

.EXAMPLE
'Sql1','Sql2/sqlexpress' | Get-DbaDatabaseUdf

Gets the User Defined Functions for the databases on Sql1 and Sql2/sqlexpress

#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemUdf,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $databases = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $databases) {

                $UserDefinedFunctions = $db.UserDefinedFunctions

                if (!$UserDefinedFunctions) {
                    Write-Message -Message "No User Defined Functions exist in the $db database on $instance" -Target $db -Level Verbose
                    continue
                }
                if (Test-Bound -ParameterName ExcludeSystemUdf) {
                    $UserDefinedFunctions = $UserDefinedFunctions | Where-Object { $_.IsSystemObject -eq $false }
                }

                $UserDefinedFunctions | foreach {

                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name ComputerName -value $server.NetName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name Database -value $db.Name

                    Select-DefaultView -InputObject $_ -Property ComputerName, InstanceName, SqlInstance, Database, Schema, CreateDate, DateLastModified, Name, DataType
                }
            }
        }
    }
}