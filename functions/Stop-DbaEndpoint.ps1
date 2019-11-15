function Stop-DbaEndpoint {
    <#
    .SYNOPSIS
        Stops endpoints on a SQL Server instance.

    .DESCRIPTION
        Stops endpoints on a SQL Server instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Endpoint
        Only stop specific endpoints.

    .PARAMETER AllEndpoints
        Stops all endpoints on an instance.

    .PARAMETER InputObject
        Enables piping from Get-Endpoint.

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
        https://dbatools.io/Stop-DbaEndpoint

    .EXAMPLE
        PS C:\> Stop-DbaEndpoint -SqlInstance sql2017a -AllEndpoints

        Stops all endpoints on the sqlserver2014 instance.

    .EXAMPLE
        PS C:\> Stop-DbaEndpoint -SqlInstance sql2017a -Endpoint endpoint1,endpoint2

        Stops the endpoint1 and endpoint2 endpoints.

    .EXAMPLE
        PS C:\> Get-Endpoint -SqlInstance sql2017a -Endpoint endpoint1 | Stop-DbaEndpoint

        Stops the endpoints returned from the Get-Endpoint command.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$EndPoint,
        [switch]$AllEndpoints,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Endpoint[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance) -And (Test-Bound -Not -ParameterName Endpoint, AllEndpoints)) {
            Stop-Function -Message "You must specify AllEndpoints or Endpoint when using the SqlInstance parameter."
            return
        }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaEndpoint -SqlInstance $instance -SqlCredential $SqlCredential -EndPoint $Endpoint
        }

        foreach ($ep in $InputObject) {
            try {
                if ($Pscmdlet.ShouldProcess($ep.Parent.Name, "Stopping $ep")) {
                    $ep.Stop()
                    $ep
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}