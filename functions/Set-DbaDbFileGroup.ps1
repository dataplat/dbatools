function Set-DbaDbFileGroup {
    <#
    .SYNOPSIS
        Sets the options for a filegroup.

    .DESCRIPTION
        Sets the options for a filegroup for the specified database(s).

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
        The name(s) of the filegroup(s).

    .PARAMETER Default
        Specifies if the filegroup should be the default. Only one filegroup in a database can be specified as the default.

    .PARAMETER ReadOnly
        Specifies the filegroup should be readonly.

    .PARAMETER ReadWrite
        Specifies the filegroup should be readwrite.

    .PARAMETER AutoGrowAllFiles
        Specifies the filegroup should auto grow all files if one file has met the threshold to auto grow.

    .PARAMETER AutoGrowSingleFile
        Specifies the filegroup should not auto grow all files.

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase and Get-DbaDbFileGroup.

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
        https://dbatools.io/Set-DbaDbFileGroup

    .EXAMPLE
        PS C:\>Set-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroup HRFG1 -Default -AutoGrowAllFiles

        Sets the HRFG1 filegroup to auto grow all files and makes it the default filegroup on the TestDb database on the sqldev1 instance.

    .EXAMPLE
        PS C:\>Set-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroup HRFG1 -AutoGrowSingleFile

        Sets the HRFG1 filegroup to not auto grow all files on the TestDb database on the sqldev1 instance.

    .EXAMPLE
        PS C:\>Set-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroup HRFG1 -ReadOnly

        Sets the HRFG1 filegroup to read only on the TestDb database on the sqldev1 instance.

    .EXAMPLE
        PS C:\>Set-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroup HRFG1 -ReadWrite

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
        [switch]$ReadWrite,
        [switch]$AutoGrowAllFiles,
        [switch]$AutoGrowSingleFile,
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
                    if ($Default.IsPresent) {
                        $fgToModify.IsDefault = $true
                    }

                    if ($ReadOnly.IsPresent) {
                        $fgToModify.ReadOnly = $true
                    }

                    if ($ReadWrite.IsPresent) {
                        $fgToModify.ReadOnly = $false
                    }

                    if ($AutoGrowAllFiles.IsPresent) {
                        $fgToModify.AutogrowAllFiles = $true
                    }

                    if ($AutoGrowSingleFile.IsPresent) {
                        $fgToModify.AutogrowAllFiles = $false
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