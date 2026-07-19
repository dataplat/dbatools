function Remove-DbaDbMirror {
    <#
    .SYNOPSIS
        Breaks database mirroring partnerships and stops mirroring sessions

    .DESCRIPTION
        Terminates database mirroring sessions by breaking the partnership between principal and mirror databases. This command stops the mirroring relationship completely, which is useful when decommissioning mirrors, performing maintenance that requires breaking the partnership, or during disaster recovery scenarios where you need to bring a database online independently.

        Important: This function only breaks the mirroring partnership - it does not automatically recover databases that are left in a "Restoring" state. You'll need to manually restore those databases with RECOVERY to make them accessible for normal operations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the names of databases whose mirroring partnerships should be terminated. Accepts multiple database names.
        Required when using SqlInstance parameter. Use this to target specific mirrored databases rather than processing all databases on the instance.

    .PARAMETER InputObject
        Accepts database objects from the pipeline, typically from Get-DbaDatabase.
        Use this when you want to filter databases using Get-DbaDatabase's capabilities before breaking mirroring partnerships.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per database where the mirroring partnership was removed.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The name of the database where mirroring was removed
        - Status: Status of the operation (always "Removed" on success)

    .NOTES
        Tags: Mirroring, Mirror, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbMirror

    .EXAMPLE
        PS C:\> Remove-DbaDbMirror -SqlInstance localhost -Database TestDB

        Stops the database mirroring session for the TestDB on the localhost instance.

    .EXAMPLE
        PS C:\> Remove-DbaDbMirror -SqlInstance localhost -Database TestDB1, TestDB2

        Stops the database mirroring session for the TestDB1 and TestDB2 databases on the localhost instance.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance localhost -Database TestDB1, TestDB2 | Remove-DbaDbMirror

        Stops the database mirroring session for the TestDB1 and TestDB2 databases on the localhost instance.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
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

        foreach ($db in $InputObject) {
            if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Turning off mirror for $db")) {
                # use t-sql cuz $db.Alter() does not always work against restoring dbs
                try {
                    try {
                        $db.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
                        $db.Alter()
                    } catch {
                        # The $db.Alter() command may both succeed and return an error code related to the mirror session being stopped.
                        # Refresh the db state and if the mirror session is still active then run the ALTER statement.
                        $db.Refresh()
                        if ($db.IsMirroringEnabled) {
                            try {
                                $db.Parent.Query("ALTER DATABASE $db SET PARTNER OFF")
                            } catch {
                                Stop-Function -Message "Failure on $($db.Parent) for $db" -ErrorRecord $_ -Continue
                            }
                        }
                    }
                    [PSCustomObject]@{
                        ComputerName = $db.ComputerName
                        InstanceName = $db.InstanceName
                        SqlInstance  = $db.SqlInstance
                        Database     = $db.Name
                        Status       = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure on $($db.Parent.Name)" -ErrorRecord $_
                }
            }
        }
    }
}