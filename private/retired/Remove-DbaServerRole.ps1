function Remove-DbaServerRole {
    <#
    .SYNOPSIS
        Removes custom server-level roles from SQL Server instances.

    .DESCRIPTION
        Removes custom server-level roles that are no longer needed from SQL Server instances. This function helps clean up security configurations by permanently dropping user-defined server roles while preserving built-in system roles. Use this when decommissioning applications, consolidating permissions, or cleaning up after security audits. The operation requires confirmation due to its permanent nature and potential security impact.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ServerRole
        Specifies the name of the custom server-level role to remove from the SQL Server instance.
        Only user-defined server roles can be removed - built-in roles like sysadmin or serveradmin are protected.
        Use this when you need to clean up obsolete custom roles after application decommissioning or security reviews.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER InputObject
        Accepts server role objects from Get-DbaServerRole for pipeline operations.
        Use this when you need to remove multiple roles or want to filter roles before removal.
        Allows for more complex scenarios like removing all custom roles that match specific criteria.

    .OUTPUTS
        PSCustomObject

        Returns one object per server role removed, with the following properties:

        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - ServerRole: The name of the server role that was dropped
        - Status: The result of the removal operation ("Success" or "Failed")

    .NOTES
        Tags: Role, Login
        Author: Claudio Silva (@ClaudioESSilva), claudioessilva.com
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaServerRole

    .EXAMPLE
        PS C:\> Remove-DbaServerRole -SqlInstance Server1 -ServerRole 'serverExecuter'

        Server-role 'serverExecuter' on Server1 will be removed if it exists.

    .EXAMPLE
        PS C:\> Remove-DbaServerRole -SqlInstance Server1 -ServerRole 'serverExecuter' -Confirm:$false

        Suppresses all prompts to remove the server-role 'serverExecuter' on 'Server1'.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$ServerRole,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.ServerRole[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaServerRole -SqlInstance $SqlInstance -SqlCredential $SqlCredential -ServerRole $ServerRole
        }

        foreach ($srvrole in $InputObject) {
            if ($Pscmdlet.ShouldProcess($srvrole.DomainInstanceName, "Dropping the server-role named $($srvrole.Role) on $($srvrole.DomainInstanceName)")) {
                try {
                    $srvrole.Drop()

                    [PSCustomObject]@{
                        ComputerName = $srvrole.ComputerName
                        InstanceName = $srvrole.InstanceName
                        SqlInstance  = $srvrole.SqlInstance
                        ServerRole   = $srvrole.Role
                        Status       = "Success"
                    }
                } catch {
                    Stop-Function -Message "Failed to drop server-role named $($srvrole.Name) on $($srvrole.Name)." -Target $srvrole -ErrorRecord $_ -Continue

                    [PSCustomObject]@{
                        ComputerName = $srvrole.ComputerName
                        InstanceName = $srvrole.InstanceName
                        SqlInstance  = $srvrole.SqlInstance
                        ServerRole   = $srvrole.Role
                        Status       = "Failed"
                    }
                }
            }
        }
    }
}