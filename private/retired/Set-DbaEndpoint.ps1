function Set-DbaEndpoint {
    <#
    .SYNOPSIS
        Modifies SQL Server endpoint properties including owner and protocol type.

    .DESCRIPTION
        Modifies properties of existing SQL Server endpoints such as changing the owner for security compliance or switching the endpoint type between DatabaseMirroring, ServiceBroker, Soap, and TSql protocols. This is commonly used when transferring endpoint ownership during security audits, changing communication protocols for availability group configurations, or updating Service Broker endpoints for application messaging. The function works with specific endpoints by name or can target all endpoints on an instance, making it useful for bulk administrative changes across your SQL Server environment.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Owner
        Specifies the new login name to assign as the endpoint owner. Common during security compliance audits when transferring endpoint ownership from individual accounts to service accounts or when standardizing endpoint ownership across your environment.

    .PARAMETER Type
        Changes the endpoint protocol type between DatabaseMirroring, ServiceBroker, Soap, or TSql. Use DatabaseMirroring for availability group configurations, ServiceBroker for application messaging, TSql for custom client connections, or Soap for web service integrations.

    .PARAMETER Endpoint
        Specifies the name(s) of specific endpoints to modify. Accepts multiple endpoint names and wildcards for pattern matching. Use when you need to update only certain endpoints rather than all endpoints on the instance.

    .PARAMETER AllEndpoints
        Modifies all endpoints found on the target SQL Server instance. Useful for bulk administrative changes like standardizing endpoint ownership or protocol types across your entire server environment.

    .PARAMETER InputObject
        Accepts endpoint objects from the pipeline, typically from Get-DbaEndpoint. This allows you to filter endpoints with Get-DbaEndpoint first, then pipe the results for modification, providing precise control over which endpoints get updated.

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
        https://dbatools.io/Set-DbaEndpoint

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Endpoint

        Returns one modified Endpoint object for each endpoint that was changed. The endpoint object reflects the updated property values after the Alter() operation is committed.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the endpoint
        - EndpointType: The type of endpoint (DatabaseMirroring, ServiceBroker, Soap, or TSql)
        - ProtocolType: The communication protocol used by the endpoint
        - Owner: The login name that owns the endpoint
        - IsSystemObject: Boolean indicating if this is a system endpoint
        - CreateDate: DateTime when the endpoint was created

        All properties from the SMO Endpoint object are accessible using Select-Object * for more detailed analysis.

    .EXAMPLE
        PS C:\> Set-DbaEndpoint -SqlInstance sql2016 -AllEndpoints -Owner sa

        Sets all endpoint owners to sa on sql2016

    .EXAMPLE
        PS C:\> Get-DbaEndpoint -SqlInstance sql2016 -Endpoint ep1 | Set-DbaEndpoint -Type TSql

        Changes the endpoint type to Tsql on endpoint ep1
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Endpoint,
        [string]$Owner,
        [ValidateSet('DatabaseMirroring', 'ServiceBroker', 'Soap', 'TSql')]
        [string]$Type,
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

        $props = "Owner", "Type"
        foreach ($ep in $InputObject) {
            try {
                if ($Pscmdlet.ShouldProcess($ep.Parent.Name, "Seting properties on $ep")) {
                    foreach ($prop in $props) {
                        if ($prop -eq "Type") {
                            $realprop = "EndpointType"
                            if (Test-Bound -ParameterName $prop) {
                                $ep.$realprop = (Get-Variable -Name $prop -ValueOnly)
                            }
                        } elseif (Test-Bound -ParameterName $prop) {
                            $ep.$prop = (Get-Variable -Name $prop -ValueOnly)
                        }
                    }
                    $ep.Alter()
                    $ep
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}