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
        Specifies the unique name for the Database Mail account being created. This name is used internally by SQL Server to identify the account when configuring Database Mail profiles.
        Choose a descriptive name that identifies the account's purpose, such as 'MaintenanceAlerts' or 'ReportDelivery'.

    .PARAMETER DisplayName
        Sets the friendly name that appears in the 'From' field of outgoing emails. Recipients see this name instead of the raw account name.
        Defaults to the Account name if not specified. Use descriptive names like 'SQL Server Alerts' or 'DBA Team Notifications'.

    .PARAMETER Description
        Provides optional documentation text describing the account's purpose and usage. This helps other DBAs understand when and how the account should be used.
        Consider including details like which jobs or applications use this account and any special configuration requirements.

    .PARAMETER EmailAddress
        Specifies the sender email address that appears in outgoing messages from this Database Mail account. This must be a valid email address that your SMTP server accepts.
        Use addresses that recipients will recognize and trust, such as 'sqlserver@company.com' or 'dba-alerts@domain.local'.

    .PARAMETER ReplyToAddress
        Specifies an alternate email address for replies when different from the sender address. Recipients who reply to automated emails will send responses to this address instead.
        Useful when you want replies to go to a monitored mailbox like 'dba-team@company.com' rather than the automated sender address.

    .PARAMETER MailServer
        Specifies the SMTP server hostname or IP address that SQL Server will use to send emails through this account. The server must be accessible from the SQL Server instance.
        If not specified, uses the SQL Server instance name as the mail server. The function validates that the mail server exists unless -Force is used.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        Bypasses the mail server existence validation and creates the Database Mail account even if the specified SMTP server cannot be found or verified.
        Use this when the mail server exists but is not discoverable by SQL Server, or when setting up accounts for servers that will be available later.

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

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Mail.MailAccount

        Returns a newly created MailAccount object from the specified SQL Server instance.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Id: Unique identifier for the mail account
        - Name: Name of the mail account
        - DisplayName: Friendly name that appears in the 'From' field of emails
        - Description: Description of the account's purpose
        - EmailAddress: Sender email address for outgoing messages
        - ReplyToAddress: Alternate email address for replies
        - IsBusyAccount: Boolean indicating if the account is currently processing emails
        - MailServers: Collection of mail servers associated with this account

        Additional properties available (from SMO MailAccount object):
        - Parent: Reference to the parent SqlMail object
        - State: Current state of the object (Existing, Creating, Pending, Dropping, etc.)
        - Urn: The Uniform Resource Name of the mail account object

        All properties from the base SMO object are accessible using Select-Object *.

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