function Set-DbaResourceGovernor {
    <#
    .SYNOPSIS
        Sets the Resource Governor feature on the specified SQL Server to be enabled or disabled,
        along with specifying an optional classifier function.

    .DESCRIPTION
        In order to utilize Resource Governor, it has to be enabled for an instance and
        have a classifier function specified. This function toggles the enabled status
        and sets the classifier function.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the Windows server as a different user

    .PARAMETER Enabled
        Enables the Resource Governor.

    .PARAMETER Disabled
        Disables the Resource Governor.

    .PARAMETER ClassifierFunction
        Sets the classifier function for Resource Governor.

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
        Author: John McCall (@lowlydba), lowlydba.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaResourceGovernor

    .EXAMPLE
        PS C:\> Set-DbaResourceGovernor -SqlInstance sql2016 -Enabled

        Sets Resource Governor to enabled for the instance sql2016.

    .EXAMPLE
        PS C:\> Set-DbaResourceGovernor -SqlInstance sql2012\dev1 -Disabled

        Sets Resource Governor to disabled for the instance dev1 on sq2012.

    .EXAMPLE
        PS C:\> Set-DbaResourceGovernor -SqlInstance sql2012\dev1 -ClassifierFunction 'fnRGClassifier' -Enabled

        Sets Resource Governor to enabled for the instance dev1 on sq2012 and sets the classifier function to be 'fnRGClassifier'.

    .EXAMPLE
        PS C:\> Set-DbaResourceGovernor -SqlInstance sql2012\dev1 -ClassifierFunction 'NULL' -Enabled

        Sets Resource Governor to enabled for the instance dev1 on sq2012 and sets the classifier function to be NULL.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [switch]$Enabled,
        [switch]$Disabled,
        [string]$ClassifierFunction,
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
            $resourceGovernorClassifierFunction = [string]$server.ResourceGovernor.ClassifierFunction

            # Set Enabled status
            if ($Enabled) {
                if ($PSCmdlet.ShouldProcess($instance, "Changing Resource Governor enabled from '$resourceGovernorState' to 'True' at the instance level")) {
                    try {
                        $server.ResourceGovernor.Enabled = $true
                    } catch {
                        Stop-Function -Message "Couldn't enable Resource Governor" -ErrorRecord $_ -Continue
                    }
                }
            } elseif ($Disabled) {
                if ($PSCmdlet.ShouldProcess($instance, "Changing Resource Governor enabled from '$resourceGovernorState' to 'False' at the instance level")) {
                    try {
                        $server.ResourceGovernor.Enabled = $false
                    } catch {
                        Stop-Function -Message "Couldn't disable Resource Governor" -ErrorRecord $_ -Continue
                    }
                }
            }

            # Set Classifier Function
            if ($ClassifierFunction) {
                if ($PSCmdlet.ShouldProcess($instance, "Changing Resource Governor Classifier Function from '$resourceGovernorClassifierFunction' to '$ClassifierFunction'")) {
                    if ($ClassifierFunction -eq "NULL") {
                        $server.ResourceGovernor.ClassifierFunction = $ClassifierFunction
                    } else {
                        $objClassifierFunction = Get-DbaDbUdf -SqlInstance $instance -SqlCredential $SqlCredential -Database "master" -Name $ClassifierFunction
                        if ($objClassifierFunction) {
                            $server.ResourceGovernor.ClassifierFunction = $objClassifierFunction
                        } else {
                            Stop-Function -Message "Classifier function '$ClassifierFunction' does not exist." -Category ObjectNotFound -Continue
                        }
                    }
                }
            }

            # Execute
            if ($PSCmdlet.ShouldProcess($instance, "Changing Resource Governor")) {
                $server.ResourceGovernor.Alter()
                $server.ResourceGovernor.Refresh()
            }

            Get-DbaResourceGovernor -SqlInstance $server
        }
    }
}