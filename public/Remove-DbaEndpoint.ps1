function Remove-DbaEndpoint {
    <#
    .SYNOPSIS
        Removes SQL Server endpoints including DatabaseMirroring, ServiceBroker, Soap, and TSql types.

    .DESCRIPTION
        Removes SQL Server endpoints by executing DROP ENDPOINT commands against the target instance. This function handles DatabaseMirroring, ServiceBroker, Soap, and TSql endpoint types, making it useful for decommissioning unused services, cleaning up after failed deployments, or hardening SQL Server instances by removing unnecessary network entry points. You can target specific endpoints by name or remove all endpoints at once, with confirmation prompts to prevent accidental deletions.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Endpoint
        Specifies the names of specific endpoints to remove from the SQL Server instance. Accepts multiple endpoint names as an array.
        Use this when you need to selectively remove particular endpoints like 'Mirroring' or custom service broker endpoints while leaving others intact.

    .PARAMETER AllEndpoints
        Removes all user-defined endpoints from the SQL Server instance, excluding system endpoints that cannot be dropped.
        Use this for complete endpoint cleanup during decommissioning or when hardening an instance by removing all custom network entry points.

    .PARAMETER InputObject
        Accepts endpoint objects from the pipeline, typically from Get-DbaEndpoint output. Allows for filtering endpoints before removal.
        Use this when you need to apply complex filtering logic or when chaining endpoint discovery and removal operations together.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Endpoint
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaEndpoint

    .EXAMPLE
        PS C:\> Remove-DbaEndpoint -SqlInstance sqlserver2012 -AllEndpoints

        Removes all endpoints on the sqlserver2014 instance. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Remove-DbaEndpoint -SqlInstance sqlserver2012 -Endpoint endpoint1,endpoint2 -Confirm:$false

        Removes the endpoint1 and endpoint2 endpoints. Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaEndpoint -SqlInstance sqlserver2012 -Endpoint endpoint1 | Remove-DbaEndpoint

        Removes the endpoints returned from the Get-DbaEndpoint function. Prompts for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Endpoint,
        [switch]$AllEndpoints,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Endpoint[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Endpoint, AllEndpoints)) {
            Stop-Function -Message "You must specify AllEndpoints or Endpoint when using the SqlInstance parameter."
            return
        }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaEndpoint -SqlInstance $instance -SqlCredential $SqlCredential -Endpoint $Endpoint
        }

        foreach ($ep in $InputObject) {
            if ($Pscmdlet.ShouldProcess($ep.Parent.name, "Removing endpoint $ep")) {
                try {
                    # avoid enumeration issues
                    $ep.Parent.Query("DROP ENDPOINT $ep")
                    [PSCustomObject]@{
                        ComputerName = $ep.ComputerName
                        InstanceName = $ep.InstanceName
                        SqlInstance  = $ep.SqlInstance
                        Endpoint     = $ep.Name
                        Status       = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}