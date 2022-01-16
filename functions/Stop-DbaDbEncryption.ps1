function Stop-DbaDbEncryption {
    <#
    .SYNOPSIS
        Decrypts all databases on an instance

    .DESCRIPTION
        Decrypts all databases on an instance

        Removes the encryption key but does not touch certificates or master keys

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2022 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Stop-DbaDbEncryption

    .EXAMPLE
        PS C:\> Stop-DbaDbEncryption -SqlInstance sql01

        Removes this does that

    .EXAMPLE
        PS C:\> Stop-DbaDbEncryption -SqlInstance sql01 -Confirm:$false

        Removes this does that
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    process {
        $param = @{
            SqlInstance   = $SqlInstance
            SqlCredential = $SqlCredential
        }
        $InputObject = Get-DbaDatabase @param | Where-Object Name -NotIn 'master', 'model', 'tempdb', 'msdb', 'resource'

        $stepCounter = 0
        foreach ($db in $InputObject) {
            $server = $db.Parent
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Disabling encryption for $($db.Name) on $($server.Name)" -TotalSteps $InputObject.Count
            try {
                if ($db.EncryptionEnabled) {
                    $db | Disable-DbaDbEncryption -Confirm:$false
                } else {
                    Write-Message -Level Verbose "Encryption was not enabled for $($db.Name) on $($server.Name)"
                    $db | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, 'Name as DatabaseName', EncryptionEnabled
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}