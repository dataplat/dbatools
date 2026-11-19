function Get-DbaDbFileGrowth {
    <#
    .SYNOPSIS
        Retrieves database file auto-growth settings and maximum size limits

    .DESCRIPTION
        Retrieves auto-growth configuration for data and log files across SQL Server databases, including growth type (percentage or fixed MB), growth increment values, and maximum size limits. This function helps DBAs quickly identify databases with problematic growth settings like percentage-based growth on large files, unlimited growth configurations, or insufficient growth increments that could cause performance issues during auto-growth events.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to analyze for file growth settings. Accepts wildcards for pattern matching.
        Use this when you need to check growth configuration for specific databases instead of all databases on the instance.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase via pipeline input.
        Use this when you want to analyze file growth settings for databases already retrieved by another dbatools command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, Data, File, Log
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbFileGrowth

    .OUTPUTS
        PSCustomObject

        Returns one object per database file across all specified databases.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: Name of the database containing the file
        - MaxSize: Maximum size the file can grow to - displays as dbasize object (KB, MB, GB, etc.)
        - GrowthType: How the file grows - either "Percent" or "kb"
        - Growth: Growth increment value - interpretation depends on GrowthType (percentage or KB)
        - File: Logical name of the file within SQL Server (aliased from LogicalName)
        - FileName: Operating system file path (aliased from PhysicalName)
        - State: Current state of the file (ONLINE, OFFLINE, etc.)

        Additional properties available (from Get-DbaDbFile object):
        - DatabaseID: Internal ID of the database
        - FileGroupName: Name of the filegroup containing this file (NULL for log files)
        - ID: File ID within the database
        - Type: Type of file - 0 for data file, 1 for log file (Integer)
        - TypeDescription: Human-readable file type (ROWS or LOG)
        - LogicalName: Logical name of the file within SQL Server
        - PhysicalName: Operating system file path
        - NextGrowthEventSize: Size that will be added during the next autogrow event - displays as dbasize object
        - Size: Current size of the file - displays as dbasize object
        - UsedSpace: Space currently used within the file - displays as dbasize object
        - AvailableSpace: Free space within the file (Size - UsedSpace) - displays as dbasize object
        - IsOffline: Boolean indicating if the file is offline
        - IsReadOnly: Boolean indicating if the file is read-only
        - IsReadOnlyMedia: Boolean indicating if the underlying storage media is read-only
        - IsSparse: Boolean indicating if the file is sparse (snapshots)
        - NumberOfDiskWrites: Count of write operations to the file since instance startup
        - NumberOfDiskReads: Count of read operations from the file since instance startup
        - ReadFromDisk: Total bytes read from the file since instance startup - displays as dbasize object
        - WrittenToDisk: Total bytes written to the file since instance startup - displays as dbasize object
        - VolumeFreeSpace: Free space available on the volume containing this file - displays as dbasize object
        - FileGroupDataSpaceId: Internal ID of the filegroup data space
        - FileGroupType: Type of filegroup (NULL for log files, or name for data filegroups)
        - FileGroupTypeDescription: Description of filegroup type
        - FileGroupDefault: Boolean indicating if this is the default filegroup
        - FileGroupReadOnly: Boolean indicating if the filegroup is read-only

        All properties from the base object are accessible even though only default properties are displayed without using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaDbFileGrowth -SqlInstance sql2017, sql2016, sql2012

        Gets all database file growths on sql2017, sql2016, sql2012

    .EXAMPLE
        PS C:\> Get-DbaDbFileGrowth -SqlInstance sql2017, sql2016, sql2012 -Database pubs

        Gets the database file growth info for pubs on sql2017, sql2016, sql2012

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database test | Get-DbaDbFileGrowth

        Gets the test database file growth information on sql2016
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound Database) -and -not (Test-Bound SqlInstance)) {
            Stop-Function -Message "You must specify SqlInstance when specifying Database"
            return
        }

        $dbs = Get-DbaDbFile @PSBoundParameters
        foreach ($db in $dbs) {
            $db | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, MaxSize, GrowthType, Growth, 'LogicalName as File', 'PhysicalName as FileName', State
        }
    }
}