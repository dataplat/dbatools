function Set-DbaDbFileGroup {
    <#
    .SYNOPSIS
        Modifies filegroup properties including default designation, read-only status, and auto-grow behavior.

    .DESCRIPTION
        Modifies key properties of database filegroups including setting the default filegroup for new objects, changing read-only status for data archival, and configuring auto-grow behavior across all files in the filegroup. Use this when you need to restructure database storage layout, implement data archival strategies, or optimize file growth patterns. The function validates that filegroups exist and contain at least one file before applying changes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases contain the filegroups to modify. Required when using SqlInstance parameter.
        Use this to target specific databases when working with filegroup configurations across multiple databases.

    .PARAMETER FileGroup
        Specifies the name(s) of the filegroup(s) to modify. The filegroup must exist and contain at least one file.
        Use this to target specific filegroups when you need to change their default status, read-only setting, or auto-grow behavior.

    .PARAMETER Default
        Sets the filegroup as the default filegroup for new database objects like tables and indexes.
        Use this when restructuring storage layout or when you want new objects created in a specific filegroup instead of PRIMARY.

    .PARAMETER ReadOnly
        Controls the read-only status of the filegroup to prevent data modifications for archival or compliance purposes.
        Set to $true for read-only (common for historical data), or $false to restore read-write access.

    .PARAMETER AutoGrowAllFiles
        Enables proportional growth across all files in the filegroup when any file reaches its growth threshold.
        Use this to maintain balanced file sizes and prevent hotspots, especially important for tempdb and high-transaction filegroups.

    .PARAMETER InputObject
        Accepts database or filegroup objects from Get-DbaDatabase or Get-DbaDbFileGroup via pipeline.
        Use this for efficient processing when working with multiple databases or filegroups from previous commands.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, Data, File
        Author: Adam Lancaster, github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbFileGroup

    .EXAMPLE
        PS C:\>Set-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroup HRFG1 -Default -AutoGrowAllFiles

        Sets the HRFG1 filegroup to auto grow all files and makes it the default filegroup on the TestDb database on the sqldev1 instance.

    .EXAMPLE
        PS C:\>Set-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroup HRFG1 -AutoGrowAllFiles:$false

        Sets the HRFG1 filegroup to not auto grow all files on the TestDb database on the sqldev1 instance.

    .EXAMPLE
        PS C:\>Set-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroup HRFG1 -ReadOnly

        Sets the HRFG1 filegroup to read only on the TestDb database on the sqldev1 instance.

    .EXAMPLE
        PS C:\>Set-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroup HRFG1 -ReadOnly:$false

        Sets the HRFG1 filegroup to read/write on the TestDb database on the sqldev1 instance.

    .EXAMPLE
        PS C:\>Get-DbaDatabase -SqlInstance sqldev1 -Database TestDb | Set-DbaDbFileGroup -FileGroup HRFG1 -AutoGrowAllFiles

        Passes in the TestDB database from the sqldev1 instance and sets the HRFG1 filegroup to auto grow all files.

    .EXAMPLE
        PS C:\>Get-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroup HRFG1 | Set-DbaDbFileGroup -AutoGrowAllFiles

        Passes in the HRFG1 filegroup from the TestDB database on the sqldev1 instance and sets it to auto grow all files.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$FileGroup,
        [switch]$Default,
        [switch]$ReadOnly,
        [switch]$AutoGrowAllFiles,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {

        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        $fileGroupsToModify = @()

        foreach ($obj in $InputObject) {

            if ($obj -is [Microsoft.SqlServer.Management.Smo.Database]) {

                if (Test-Bound -Not -ParameterName FileGroup) {
                    Stop-Function -Message "Filegroup is required" -Continue
                }

                foreach ($fg in $FileGroup) {

                    if ($obj.FileGroups.Name -notcontains $fg) {
                        Stop-Function -Message "Filegroup $fg does not exist in the database $($obj.Name) on $($obj.Parent.Name)" -Continue
                    }

                    $fileGroupsToModify += $obj.FileGroups[$fg]
                }
            } elseif ($obj -is [Microsoft.SqlServer.Management.Smo.FileGroup]) {
                $fileGroupsToModify += $obj
            }
        }

        foreach ($fgToModify in $fileGroupsToModify) {

            if ($fgToModify.Files.Count -eq 0) {
                Stop-Function -Message "Filegroup $FileGroup is empty on $($obj.Name) on $($obj.Parent.Name). Before the options can be set there must be at least one file in the filegroup." -Continue
            }

            if ($Pscmdlet.ShouldProcess($fgToModify.Parent.Parent.Name, "Updating the filegroup options for $($fgToModify.Name) on the database $($fgToModify.Parent.Name) on $($fgToModify.Parent.Parent.Name)")) {
                try {
                    if (Test-Bound Default) {
                        $fgToModify.IsDefault = $true
                    }

                    if (Test-Bound ReadOnly) {
                        $fgToModify.ReadOnly = $ReadOnly
                    }

                    if (Test-Bound AutoGrowAllFiles) {
                        $fgToModify.AutogrowAllFiles = $AutoGrowAllFiles
                    }

                    $fgToModify.Alter()
                    $fgToModify
                } catch {
                    Stop-Function -Message "Failure on $($fgToModify.Parent.Parent.Name) to set the filegroup options for $($fgToModify.Name) in the database $($fgToModify.Parent.Name)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}