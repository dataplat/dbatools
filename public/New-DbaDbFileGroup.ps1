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
        The target database(s).

    .PARAMETER FileGroup
        The name of the new filegroup.

    .PARAMETER FileGroupType
        The type of the file group. Possible values are "FileStreamDataFileGroup", "MemoryOptimizedDataFileGroup", "RowsFileGroup". The default is "RowsFileGroup".

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase.

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