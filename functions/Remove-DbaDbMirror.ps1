function Remove-DbaDbMirror {
    <#
    .SYNOPSIS
        Removes database mirrors.

    .DESCRIPTION
        Removes database mirrors. Does not set databases in recovery to recovered.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The target database.

    .PARAMETER Partner
        The partner Fully Qualified Domain Name.

    .PARAMETER Witness
        The witness Fully Qualified Domain Name.

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
        Tags: Mirroring, Mirror, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbMirror

    .EXAMPLE
        PS C:\> Set-DbaDbMirror -SqlInstance localhost

        Returns all Endpoint(s) on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Set-DbaDbMirror -SqlInstance localhost, sql2016

        Returns all Endpoint(s) for the local and sql2016 SQL Server instances
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
                        try {
                            $db.Parent.Query("ALTER DATABASE $db SET PARTNER OFF")
                        } catch {
                            Stop-Function -Message "Failure on $($db.Parent) for $db" -ErrorRecord $_ -Continue
                        }
                    }
                    [pscustomobject]@{
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