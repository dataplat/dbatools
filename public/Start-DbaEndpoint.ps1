function Start-DbaEndpoint {
    <#
    .SYNOPSIS
        Starts stopped SQL Server endpoints for Database Mirroring, Service Broker, and other network services.

    .DESCRIPTION
        Starts stopped SQL Server endpoints that are required for Database Mirroring, Service Broker, SOAP, and custom TCP connections. Endpoints must be in a started state to accept network connections and facilitate features like Availability Groups, database mirroring partnerships, and Service Broker message routing. This function is commonly used after maintenance windows, server restarts, or when troubleshooting connectivity issues where endpoints were inadvertently stopped.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Endpoint
        Specifies the names of specific endpoints to start on the target SQL Server instance.
        Use this when you only need to start particular endpoints like Database Mirroring or Service Broker endpoints rather than all endpoints on the server.

    .PARAMETER AllEndpoints
        Starts all endpoints on the target SQL Server instance regardless of their current state or type.
        This is required when using the SqlInstance parameter and you want to start all endpoints rather than specific ones.

    .PARAMETER InputObject
        Accepts endpoint objects from the pipeline, typically from Get-DbaEndpoint cmdlet output.
        Use this to start endpoints that have already been retrieved and filtered by other dbatools commands.

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
        https://dbatools.io/Start-DbaEndpoint

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Endpoint

        Returns the Endpoint object(s) that were successfully started.

        Properties:
        - Name: The endpoint name
        - EndpointState: The state of the endpoint (Started, Stopped, Disabled)
        - EndpointType: The type of endpoint (DatabaseMirroring, ServiceBroker, Tsql, SoapEndpoint, etc.)
        - ProtocolType: The communication protocol used (TCP, NamedPipes, SharedMemory)
        - Owner: The owner of the endpoint
        - IsAdminEndpoint: Boolean indicating if this is an administrative endpoint
        - IsSystemObject: Boolean indicating if this is a system-created endpoint
        - ID: Unique identifier for the endpoint
        - Parent: References the parent Server object

    .EXAMPLE
        PS C:\> Start-DbaEndpoint -SqlInstance sqlserver2012 -AllEndpoints

        Starts all endpoints on the sqlserver2014 instance.

    .EXAMPLE
        PS C:\> Start-DbaEndpoint -SqlInstance sqlserver2012 -Endpoint endpoint1,endpoint2 -SqlCredential sqladmin

        Logs into sqlserver2012 using alternative credentials and starts the endpoint1 and endpoint2 endpoints.

    .EXAMPLE
        PS C:\> Get-Endpoint -SqlInstance sqlserver2012 -Endpoint endpoint1 | Start-DbaEndpoint

        Starts the endpoints returned from the Get-Endpoint function.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
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
                if ($Pscmdlet.ShouldProcess($ep.Parent.Name, "Starting $ep")) {
                    $ep.Start()
                    $ep
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}