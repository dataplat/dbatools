function Enable-DbaReplDistributor {
    <#
    .SYNOPSIS
        Enables replication distribution for the target SQL instances.

    .DESCRIPTION
        Enables replication distribution for the target SQL instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DistributionDatabase
        Name of the distribution database that will be created.

        Default is 'distribution'.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Replication
        Author: Jess Pomfret (@jpomfret)

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Enable-DbaReplDistributor

    .EXAMPLE
        PS C:\> Enable-DbaReplDistributor -SqlInstance mssql1

        Enables distribution for the mssql1 instance.

    .EXAMPLE
        PS C:\> Enable-DbaReplDistributor -SqlInstance mssql1 -DistributionDatabase repDatabase

        Enables distribution for the mssql1 instance and names the distribution database repDatabase.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$DistributionDatabase = 'distribution',
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Enabling replication distribution for $instance"

            try {
                if ($PSCmdlet.ShouldProcess($instance, "Enabling distributor for $instance")) {
                    $distributionDb = New-Object Microsoft.SqlServer.Replication.DistributionDatabase
                    $distributionDb.ConnectionContext = $replServer.ConnectionContext
                    $distributionDb.Name = $DistributionDatabase
                    # lots more properties to add as params
                    $replServer.InstallDistributor($null, $distributionDb)
                }
            } catch {
                Stop-Function -Message "Unable to enable replication distributor" -ErrorRecord $_ -Target $instance -Continue
            }

            $replServer.Refresh()
            $replServer

        }
    }
}



