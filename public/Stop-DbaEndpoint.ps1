function Stop-DbaEndpoint {
    <#
    .SYNOPSIS
        Stops SQL Server communication endpoints like Service Broker, Database Mirroring, or custom TCP endpoints.

    .DESCRIPTION
        Stops specific or all SQL Server endpoints on target instances. Endpoints are communication channels that SQL Server uses for features like Service Broker messaging, Database Mirroring, Availability Groups, and custom applications. You might need to stop endpoints during maintenance windows, troubleshooting connectivity issues, or when decommissioning specific services. This command safely stops the endpoints without dropping them, so they can be restarted later with Start-DbaEndpoint.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Endpoint
        Specifies the names of specific endpoints to stop. Accepts multiple endpoint names as an array.
        Use this when you need to stop only certain endpoints while leaving others running, such as stopping a Service Broker endpoint for maintenance while keeping Database Mirroring endpoints active.

    .PARAMETER AllEndpoints
        Stops all endpoints on the specified SQL Server instance. Required when using SqlInstance parameter if Endpoint is not specified.
        Use this during full maintenance windows or when you need to completely disable all endpoint communication for troubleshooting network connectivity issues.

    .PARAMETER InputObject
        Accepts endpoint objects from Get-DbaEndpoint for pipeline operations. Allows filtering and processing endpoints before stopping them.
        Use this for complex scenarios where you need to filter endpoints based on their properties before stopping them.

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

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Endpoint

        Returns the endpoint object(s) after they have been successfully stopped. One object is returned per endpoint that was stopped.

        Default display properties (via Select-DefaultView in Get-DbaEndpoint):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - ID: The endpoint identifier
        - Name: The name of the endpoint
        - IPAddress: The IP address the endpoint listens on (TCP endpoints only)
        - Port: The port number the endpoint listens on (TCP endpoints only)
        - EndpointState: Current state of the endpoint (Stopped, Started, or Disabled)
        - EndpointType: Type of endpoint (ServiceBroker, DatabaseMirroring, TSql, etc.)
        - Owner: The login that owns the endpoint
        - IsAdminEndpoint: Boolean indicating if this is an admin endpoint
        - Fqdn: Fully qualified domain name with protocol and port (TCP endpoints only)
        - IsSystemObject: Boolean indicating if this is a system endpoint

        All properties from the base SMO Endpoint object are accessible using Select-Object *.

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
        [string[]]$Endpoint,
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
            $InputObject += Get-DbaEndpoint -SqlInstance $instance -SqlCredential $SqlCredential -Endpoint $Endpoint
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