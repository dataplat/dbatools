function New-DbaDbMailAccount {
    <#
    .SYNOPSIS
        Creates a new Database Mail account for sending emails from SQL Server

    .DESCRIPTION
        Creates a new Database Mail account on SQL Server instances to enable automated email notifications, alerts, and reports. Database Mail accounts define the email settings (SMTP server, sender address, authentication) that SQL Server uses when sending emails through stored procedures like sp_send_dbmail. This is essential for setting up automated maintenance notifications, job failure alerts, and scheduled report delivery.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Account
        The name of the account to be created.

    .PARAMETER DisplayName
        Sets the name of the mail account that is displayed in messages.

    .PARAMETER Description
        Sets the description of the purpose of the mail account.

    .PARAMETER EmailAddress
        Sets the e-mail address of the mail account.

    .PARAMETER ReplyToAddress
        Sets the e-mail address to which the mail account replies.

    .PARAMETER MailServer
        The name of the mail server.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Mail Account will be created even if the mail server is not present.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DatabaseMail, DbMail, Mail
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbMailAccount

    .EXAMPLE
        PS C:\> $account = New-DbaDbMailAccount -SqlInstance sql2017 -Account 'The DBA Team' -EmailAddress admin@ad.local -MailServer smtp.ad.local

        Creates a new database mail account with the email address admin@ad.local on sql2017 named "The DBA Team" using the smtp.ad.local mail server.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [Alias("Name")]
        [string]$Account,
        [string]$DisplayName = $Account,
        [string]$Description,
        [parameter(Mandatory)]
        [string]$EmailAddress,
        [string]$ReplyToAddress,
        [string]$MailServer,
        [switch]$Force,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (Test-Bound -ParameterName MailServer) {
                if (-not (Get-DbaDbMailServer -SqlInstance $server -Server $MailServer) -and -not (Test-Bound -ParameterName Force)) {
                    Stop-Function -Message "The mail server '$MailServer' does not exist on $instance. Use -Force if you need to create it anyway." -Target $instance -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($instance, "Creating new db mail account called $Account")) {
                try {
                    $accountObj = New-Object Microsoft.SqlServer.Management.SMO.Mail.MailAccount $server.Mail, $Account
                    $accountObj.DisplayName = $DisplayName
                    $accountObj.Description = $Description
                    $accountObj.EmailAddress = $EmailAddress
                    $accountObj.ReplyToAddress = $ReplyToAddress
                    $accountObj.Create()
                } catch {
                    Stop-Function -Message "Failure creating db mail account" -Target $Account -ErrorRecord $_ -Continue
                }

                try {
                    $accountObj.MailServers.Item($($server.DomainInstanceName)).Rename($MailServer)
                    $accountObj.Alter()
                    $accountObj.Refresh()
                    Add-Member -Force -InputObject $accountObj -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $accountObj -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $accountObj -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    $accountObj | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, DisplayName, Description, EmailAddress, ReplyToAddress, IsBusyAccount, MailServers
                } catch {
                    Stop-Function -Message "Failure returning output" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}