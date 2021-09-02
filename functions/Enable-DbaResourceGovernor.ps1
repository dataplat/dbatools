function Enable-DbaResourceGovernor {
    <#
    .SYNOPSIS
        Enables the Resource Governor feature on the specified SQL Server.

    .DESCRIPTION
        In order to utilize Resource Governor it has to be enabled for an instance.
        This function enables that feature for the SQL Server instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Windows server as a different user

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ResourceGovernor
        Author: John McCall (@lowlydba), https://www.lowlydba.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Enable-DbaResourceGovernor

    .EXAMPLE
        PS C:\> Enable-DbaResourceGovernor -SqlInstance sql2016

        Sets Resource Governor to enabled for the instance sql2016.

    .EXAMPLE
        PS C:\> Enable-DbaResourceGovernor -SqlInstance sql2012\dev1

        Sets Resource Governor to enabled for the instance dev1 on sq2012.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $resourceGovernorState = [bool]$server.ResourceGovernor.Enabled

            if ($PSCmdlet.ShouldProcess($instance, "Changing Resource Governor enabled from '$resourceGovernorState' to 'True' at the instance level")) {
                try {
                    $server.ResourceGovernor.Enabled = $true
                    $server.ResourceGovernor.Alter()
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }

            [PSCustomObject]@{
                ComputerName              = $server.ComputerName
                InstanceName              = $server.InstanceName
                SqlInstance               = $server.SqlInstance
                IsResourceGovernorEnabled = $true
            }
        }
    }
}