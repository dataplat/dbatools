function New-DbaDbFileGroup {
    <#
    .SYNOPSIS
        Creates new filegroups in SQL Server databases for custom data storage organization.

    .DESCRIPTION
        Creates a new filegroup for the specified database(s), supporting standard row data, FileStream, and memory-optimized storage types. This is useful when you need to separate table storage across different disk drives for performance optimization, implement compliance requirements, or organize data by department or function. The filegroup is created empty and requires adding data files with Add-DbaDbFile before it can store data. Use Set-DbaDbFileGroup to configure advanced properties like read-only status or default settings after files are added.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database(s) where the new filegroup will be created. Supports multiple database names for bulk operations.
        Use this when you need to create the same filegroup structure across multiple databases for consistency.

    .PARAMETER FileGroup
        Sets the name for the new filegroup being created. The name must be unique within the database and follow SQL Server naming conventions.
        Use descriptive names like 'HR_Data' or 'Archive_FG' to indicate the data's purpose or department for better organization.

    .PARAMETER FileGroupType
        Defines the storage type for the filegroup: RowsFileGroup for regular tables and indexes, FileStreamDataFileGroup for FILESTREAM data like documents and images, or MemoryOptimizedDataFileGroup for In-Memory OLTP tables.
        Most scenarios use the default RowsFileGroup unless you're specifically implementing FILESTREAM or In-Memory OLTP features.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase for pipeline operations. This enables you to filter databases first, then create filegroups on the selected ones.
        Useful when working with multiple databases that match specific criteria rather than specifying database names directly.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, Data, File, FileGroup
        Author: Adam Lancaster, github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.FileGroup

        Returns one FileGroup object per filegroup created. If creation fails or is skipped (e.g., filegroup already exists), no object is returned for that filegroup.

        Properties (all from SMO FileGroup object with added connection context):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Parent: The parent Database object reference
        - FileGroupType: Type of filegroup (RowsFileGroup, FileStreamFileGroup, or MemoryOptimizedFileGroup)
        - Name: Name of the filegroup (the value specified in -FileGroup parameter)
        - Size: Total size of the filegroup in kilobytes
        - AbsolutePhysicalName: Absolute physical name of the filegroup
        - DefaultFileGroup: Boolean indicating if this is the default filegroup
        - IsDefault: Boolean indicating if this is the default filegroup
        - State: State of the filegroup (Normal, Offline, Defunct)
        - Files: Collection of DataFile objects in the filegroup

        All properties from the base SMO FileGroup object are accessible using Select-Object *.

    .LINK
        https://dbatools.io/New-DbaDbFileGroup

    .EXAMPLE
        PS C:\>New-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroup HRFG1

        Creates the HRFG1 filegroup on the TestDb database on the sqldev1 instance with the default options for the filegroup.

    .EXAMPLE
        PS C:\>New-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroup HRFG1 -FileGroupType FileStreamDataFileGroup

        Creates a filestream filegroup named HRFG1 on the TestDb database on the sqldev1 instance.

    .EXAMPLE
        PS C:\>New-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroup HRFG1 -FileGroupType MemoryOptimizedDataFileGroup

        Creates a MemoryOptimized data filegroup named HRFG1 on the TestDb database on the sqldev1 instance.

    .EXAMPLE
        PS C:\>Get-DbaDatabase -SqlInstance sqldev1 -Database TestDb | New-DbaDbFileGroup -FileGroup HRFG1

        Passes in the TestDB database via pipeline and creates the HRFG1 filegroup on the TestDb database on the sqldev1 instance.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string]$FileGroup,
        [ValidateSet("FileStreamDataFileGroup", "MemoryOptimizedDataFileGroup", "RowsFileGroup")]
        [string]$FileGroupType = "RowsFileGroup",
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {

        if (Test-Bound -Not -ParameterName FileGroup) {
            Stop-Function -Message "FileGroup is required"
            return
        }

        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {

            if ($db.FileGroups.Name -contains $FileGroup) {
                Stop-Function -Message "Filegroup $FileGroup already exists in the database $($db.Name) on $($db.Parent.Name)" -Continue
            }

            if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Creating the filegroup $FileGroup on the database $($db.Name) on $($db.Parent.Name)")) {
                try {
                    $newFileGroup = New-Object Microsoft.SqlServer.Management.Smo.FileGroup -ArgumentList $db, $FileGroup

                    if (Test-Bound FileGroupType) {
                        $newFileGroup.FileGroupType = [Microsoft.SqlServer.Management.Smo.FileGroupType]::$FileGroupType
                    }

                    $newFileGroup.Create()
                    $newFileGroup
                } catch {
                    Stop-Function -Message "Failure on $($db.Parent.Name) to create the filegroup $FileGroup in the database $($db.Name)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}