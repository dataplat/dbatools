function New-DbaServiceMasterKey {
    <#
    .SYNOPSIS
        Creates a service master key in the master database for instance-level encryption hierarchy

    .DESCRIPTION
        Creates a service master key in the master database, which sits at the top of SQL Server's encryption hierarchy. The service master key automatically encrypts and protects database master keys, certificates, and other encryption objects across all databases on the instance. This is typically the first step when implementing any encryption strategy on a SQL Server instance, as it eliminates the need to manually manage individual database master key passwords.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER SecurePassword
        Secure string used to create the key.

    .PARAMETER Credential
        Enables easy creation of a secure password.

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
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaServiceMasterKey

    .EXAMPLE
        PS C:\> New-DbaServiceMasterKey -SqlInstance Server1

        You will be prompted to securely enter your Service Key password, then a master key will be created in the master database on server1 if it does not exist.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [Alias("Password")]
        [Security.SecureString]$SecurePassword,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            if ($PSCmdlet.ShouldProcess("$instance", "Creating new master key")) {
                New-DbaDbMasterKey -SqlInstance $instance -SqlCredential $SqlCredential -Database master -SecurePassword $SecurePassword -Credential $Credential
            }
        }
    }
}