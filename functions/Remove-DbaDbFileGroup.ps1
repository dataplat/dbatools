function Remove-DbaDbFileGroup {
    <#
    .SYNOPSIS
        Removes a filegroup.

    .DESCRIPTION
        Removes a filegroup. It is required that the filegroup is empty before it can be removed.

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
        The name of the filegroup.

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
        https://dbatools.io/Remove-DbaDbFileGroup

    .EXAMPLE
        PS C:\>Remove-DbaDbFileGroup -SqlInstance sqldev1 -Database TestDb -FileGroupName HRFG1

        Removes the HRFG1 filegroup on the TestDb database on the sqldev1 instance.

    .EXAMPLE
        PS C:\>Get-DbaDatabase -SqlInstance sqldev1 -Database TestDb | Remove-DbaDbFileGroup -FileGroupName HRFG1

        Passes in the TestDB database via pipeline and removes the HRFG1 filegroup on the TestDb database on the sqldev1 instance.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string]$FileGroupName,
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

            if ($db.FileGroups.Name -notcontains $FileGroupName) {
                Stop-Function -Message "Filegroup $FileGroupName does not exist in the database $($db.Name) on $($db.Parent.Name)" -Continue
            }

            if ($db.FileGroups[$FileGroupName].Files.Count -gt 0) {
                Stop-Function -Message "Filegroup $FileGroupName is not empty. Before the filegroup can be dropped the files must be removed in Filegroup $FileGroupName on $($db.Name) on $($db.Parent.Name)" -Continue
            }

            if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Removing the filegroup $FileGroupName on the database $($db.Name) on $($db.Parent.Name)")) {
                try {
                    $db.FileGroups[$FileGroupName].Drop()
                } catch {
                    Stop-Function -Message "Failure on $($db.Parent.Name) to remove the filegroup $FileGroupName in the database $($db.Name)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}