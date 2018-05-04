function Get-DbaDbPageInfo {
    <#
.SYNOPSIS
    Get-DbaDbPageInfo will return page information for a database

.DESCRIPTION
    Get-DbaDbPageInfo is able to return information about the pages in a database.
    It's possible to return the information for multiple databases and filter on specific databases, schemas and tables

.PARAMETER SqlInstance
    SQL Server name or SMO object representing the SQL Server to connect to

.PARAMETER Database
    Database to perform the restore for. This value can also be piped enabling multiple databases to be recovered.
    If this value is not supplied all databases will be recovered.

.PARAMETER SqlCredential
    Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

    $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

    Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
    To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Database
    Parameter to specify the database to get the results from

.PARAMETER Schema
    Filter to only get specific schemas

.PARAMETER Table
    Filter to only get specific tables

.PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.PARAMETER WhatIf
    Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
    Prompts you for confirmation before executing any changing operations within the command.

.EXAMPLE
    Invoke-DbaLogShippingRecovery -SqlServer server1

    Recovers all the databases on the instance that are enabled for log shipping

.NOTES
    Author: Sander Stad (@sqlstad, sqlstad.nl)
    Tags: Pages, Databases, Used space

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: MIT https://opensource.org/licenses/MIT

.LINK
    https://dbatools.io/Get-DbaDbPageInfo
#>

    [CmdLetBinding()]

    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory = $true)]
        [object[]]$Database,
        [string[]]$Schema,
        [string[]]$Table,
        [switch]$EnableException
    )

    begin {
        # Create array list to hold the results
        $collection = New-Object System.Collections.ArrayList
    }

    process {

        if (Test-FunctionInterrupt) { return }

        # Loop through all the instances
        foreach ($instance in $SqlInstance) {

            # Try connecting to the instance
            Write-Message -Message "Attempting to connect to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Get all the databases that compare to the database parameter
            $databaseCollection = $server.Databases | Where-Object {$_.Name -in $Database}

            # Loop through each of databases
            foreach ($db in $databaseCollection) {

                # Check the version of the server to setup the correct version of the query
                $query = "
SELECT ss.name AS SchemaName,
    st.name AS TableName,
    dbpa.page_type_desc AS PageType,
    dbpa.page_free_space_percent AS PageFreePercent,
    dbpa.is_allocated AS IsAllocated,
    dbpa.is_mixed_page_allocation AS IsMixedPage
FROM sys.dm_db_database_page_allocations(DB_ID(), NULL, NULL, NULL, 'DETAILED') AS dbpa
    INNER JOIN sys.tables AS st
        ON st.object_id = dbpa.object_id
    INNER JOIN sys.schemas AS ss
        ON ss.schema_id = st.schema_id;"

                # Get the results
                try {
                    $results = Invoke-DbaSqlQuery -SqlInstance $instance -Database $db.Name -Query $query

                    # Filter the results if neccesary
                    if ($Schema) {
                        $results = $results | Where-Object {$_.Schema -in $Schema}
                    }

                    if ($Table) {
                        $results = $results | Where-Object {$_.Table -in $Table}
                    }

                    # Add the results to the collection
                    $collection += $results.Foreach{
                        [PSCustomObject]@{
                            ComputerName    = $server.NetName
                            InstanceName    = $server.ServiceName
                            SqlInstance     = $server.DomainInstanceName
                            Database        = $db.Name
                            Schema          = $_.SchemaName
                            Table           = $_.TableName
                            PageType        = $_.PageType
                            PageFreePercent = $_.PageFreePercent
                            IsAllocated     = switch($_.IsAllocated){ 0 { $false } 1 { $true }}
                            IsMixedPage     = switch($_.IsMixedPage){ 0 { $false } 1 { $true }}
                        }
                    }

                }
                catch {
                    Stop-Function -Message "Something went wrong executing the query" -ErrorRecord $_ -Target $instance
                }

            } # End foreach database

        } # End foreach instance

        return $collection

    } # End process

    end {
        if (Test-FunctionInterrupt) { return }

        Write-Message -Message "Finished retrieving page count for database" -Level Verbose
    }

}