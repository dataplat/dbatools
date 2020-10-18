function Set-DbaEndpoint {
    <#
    .SYNOPSIS
        Sets endpoint properties on a SQL Server instance.

    .DESCRIPTION
        Sets endpoint properties on a SQL Server instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Owner
        Change the endpoint owner.

    .PARAMETER Type
        Change the endpoint type. Options: DatabaseMirroring, ServiceBroker, Soap, TSql

    .PARAMETER Endpoint
        Only set specific endpoint properties.

    .PARAMETER AllEndpoints
        Set all endpoint properties on an instance.

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
        https://dbatools.io/Set-DbaEndpoint

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