function Find-DbaDatabase {
    <#
    .SYNOPSIS
        Searches multiple SQL Server instances for databases matching name, owner, or Service Broker GUID patterns

    .DESCRIPTION
        Performs database discovery and inventory across multiple SQL Server instances by searching for databases that match specific criteria. You can search by database name (using regex patterns), database owner, or Service Broker GUID to locate databases across environments.

        This is particularly useful for tracking databases across development, test, and production environments, finding databases by ownership for security audits, or identifying databases with matching Service Broker GUIDs. The function returns detailed information including database size, object counts (tables, views, stored procedures), and creation details.

        Service Broker GUIDs can become mismatched on restored databases when using ALTER DATABASE...NEW_BROKER or when Service Broker is disabled, which resets the GUID to all zeros. This function helps identify such scenarios during database migrations and troubleshooting.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Property
        What you would like to search on. Either Database Name, Owner, or Service Broker GUID. Database name is the default.

    .PARAMETER Pattern
        Value that is searched for. This is a regular expression match but you can just use a plain ol string like 'dbareports'

    .PARAMETER Exact
        Search for an exact match instead of a pattern

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Lookup
        Author: Stephen Bennett, sqlnotesfromtheunderground.wordpress.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaDatabase

    .EXAMPLE
        PS C:\> Find-DbaDatabase -SqlInstance "DEV01", "DEV02", "UAT01", "UAT02", "PROD01", "PROD02" -Pattern Report

        Returns all database from the SqlInstances that have a database with Report in the name

    .EXAMPLE
        PS C:\> Find-DbaDatabase -SqlInstance "DEV01", "DEV02", "UAT01", "UAT02", "PROD01", "PROD02" -Pattern TestDB -Exact | Select-Object *

        Returns all database from the SqlInstances that have a database named TestDB with a detailed output.

    .EXAMPLE
        PS C:\> Find-DbaDatabase -SqlInstance "DEV01", "DEV02", "UAT01", "UAT02", "PROD01", "PROD02" -Property ServiceBrokerGuid -Pattern '-faeb-495a-9898-f25a782835f5' | Select-Object *

        Returns all database from the SqlInstances that have the same Service Broker GUID with a detailed output

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet('Name', 'ServiceBrokerGuid', 'Owner')]
        [string]$Property = 'Name',
        [parameter(Mandatory)]
        [string]$Pattern,
        [switch]$Exact,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($exact -eq $true) {
                $dbs = $server.Databases | Where-Object IsAccessible | Where-Object { $_.$property -eq $pattern }
            } else {
                try {
                    $dbs = $server.Databases | Where-Object IsAccessible | Where-Object { $_.$property.ToString() -match $pattern }
                } catch {
                    # they probably put asterisks thinking it's a like
                    $Pattern = $Pattern -replace '\*', ''
                    $Pattern = $Pattern -replace '\%', ''
                    $dbs = $server.Databases | Where-Object IsAccessible | Where-Object { $_.$property.ToString() -match $pattern }
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

                $res = $db.Query("
                SELECT 'proc' AS t, COUNT(*) AS numFound FROM sys.procedures WHERE is_ms_shipped = 0
                UNION ALL
                SELECT 'tables' AS t, COUNT(*) AS numFound FROM sys.tables WHERE is_ms_shipped = 0
                UNION ALL
                SELECT 'views' AS t, COUNT(*) AS numFound FROM sys.views WHERE is_ms_shipped = 0")

                [PSCustomObject]@{
                    ComputerName       = $server.ComputerName
                    InstanceName       = $server.ServiceName
                    SqlInstance        = $server.Name
                    Name               = $db.Name
                    Id                 = $db.Id
                    Size               = [dbasize]($db.Size * 1024 * 1024)
                    Owner              = $db.Owner
                    CreateDate         = $db.CreateDate
                    ServiceBrokerGuid  = $db.ServiceBrokerGuid
                    Tables             = ($res | Where-Object t -eq 'tables').numFound
                    StoredProcedures   = ($res | Where-Object t -eq 'proc').numFound
                    Views              = ($res | Where-Object t -eq 'views').numFound
                    ExtendedProperties = $extendedproperties
                }
            }
        }
    }
}