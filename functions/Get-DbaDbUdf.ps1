function Get-DbaDbUdf {
    <#
    .SYNOPSIS
        Gets database User Defined Functions

    .DESCRIPTION
        Gets database User Defined Functions

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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
        Tags: Security, Database
        Author: Klaas Vandenberghe (@PowerDbaKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbUdf

    .EXAMPLE
        PS C:\> Get-DbaDbUdf -SqlInstance sql2016

        Gets all database User Defined Functions

    .EXAMPLE
        PS C:\> Get-DbaDbUdf -SqlInstance Server1 -Database db1

        Gets the User Defined Functions for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbUdf -SqlInstance Server1 -ExcludeDatabase db1

        Gets the User Defined Functions for all databases except db1

    .EXAMPLE
        PS C:\> Get-DbaDbUdf -SqlInstance Server1 -ExcludeSystemUdf

        Gets the User Defined Functions for all databases that are not system objects (there can be 100+ system User Defined Functions in each DB)

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbUdf

        Gets the User Defined Functions for the databases on Sql1 and Sql2/sqlexpress

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemUdf,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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

                $UserDefinedFunctions | ForEach-Object {

                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name Database -value $db.Name

                    Select-DefaultView -InputObject $_ -Property ComputerName, InstanceName, SqlInstance, Database, Schema, CreateDate, DateLastModified, Name, DataType
                }
            }
        }
    }
}