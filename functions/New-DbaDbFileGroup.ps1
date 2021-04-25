function New-DbaDbFileGroup {
    <#
    .SYNOPSIS
        Creates a new filegroup.

    .DESCRIPTION
        Creates a new filegroup for the specified database(s) and allows the filegroup options to be set.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The target database(s).

    .PARAMETER FileGroupName
        The name of the new filegroup.

    .PARAMETER FileGroupType
        The type of the file group. Possible values are "FileStreamDataFileGroup", "MemoryOptimizedDataFileGroup", "RowsFileGroup". The default is "RowsFileGroup".

    .PARAMETER Default
        Specifies if the filegroup should be the default. Only one filegroup in a database can be specified as the default.

    .PARAMETER ReadOnly
        Specifies the filegroup should be readonly.

    .PARAMETER AutoGrowAllFiles
        Specifies the filegroup should auto grow all files if one file has met the threshold to autogrow.

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
        Tags: Data, Database, File, FileGroup, Migration, Partitioning, Table
        Author: Adam Lancaster https://github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbFileGroup

    .EXAMPLE
        PS C:\>New-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroupName HRFG1

        Creates the HRFG1 filegroup on the TestDb database on the sqldev1 instance and accepts the default options for the filegroup.

    .EXAMPLE
        PS C:\>New-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroupName HRFG1 -Default -AutoGrowAllFiles

        Creates the HRFG1 filegroup on the TestDb database on the sqldev1 instance and makes it the default filegroup with the option to auto-grow all files.

    .EXAMPLE
        PS C:\>New-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroupName HRFG1 -FileGroupType FileStreamDataFileGroup

        Creates a filestream filegroup named HRFG1 on the TestDb database on the sqldev1 instance and accepts the default options for the filegroup.

    .EXAMPLE
        PS C:\>New-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroupName HRFG1 -FileGroupType MemoryOptimizedDataFileGroup

        Creates a MemoryOptimized data filegroup named HRFG1 on the TestDb database on the sqldev1 instance and accepts the default options for the filegroup.

    .EXAMPLE
        PS C:\>Get-DbaDatabase -SqlInstance sqldev1 -Database TestDb | New-DbaDbFileGroup -FileGroupName HRFG1

        Passes in the TestDB database via pipeline and creates the HRFG1 filegroup on the TestDb database on the sqldev1 instance and accepts the default options for the filegroup.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string]$FileGroupName,
        [ValidateSet("FileStreamDataFileGroup", "MemoryOptimizedDataFileGroup", "RowsFileGroup")]
        [string]$FileGroupType = "RowsFileGroup",
        [switch]$Default,
        [switch]$ReadOnly,
        [switch]$AutoGrowAllFiles,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {

        if (Test-Bound -Not -ParameterName FileGroupName) {
            Stop-Function -Message "FileGroupName is required"
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

            if ($db.FileGroups.Name -contains $FileGroupName) {
                Stop-Function -Message "Filegroup $FileGroupName already exists in the database $($db.Name) on $($db.Parent.Name)" -Continue
            }

            if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Creating the filegroup $FileGroupName on the database $($db.Name)")) {
                try {
                    $newFileGroup = New-Object Microsoft.SqlServer.Management.Smo.FileGroup -ArgumentList $db, $FileGroupName

                    if (Test-Bound FileGroupType) {
                        $newFileGroup.FileGroupType = [Microsoft.SqlServer.Management.Smo.FileGroupType]::$FileGroupType
                    }

                    if ($Default.IsPresent) {
                        $newFileGroup.IsDefault = $true
                    }

                    if ($ReadOnly.IsPresent) {
                        $newFileGroup.ReadOnly = $true
                    }

                    if ($AutoGrowAllFiles.IsPresent) {
                        $newFileGroup.AutogrowAllFiles = $true
                    }

                    $newFileGroup.Create()
                    $newFileGroup
                } catch {
                    Stop-Function -Message "Failure on $($db.Parent.Name) to create the filegroup $FileGroupName in the database $($db.Name)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}