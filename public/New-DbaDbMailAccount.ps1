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

    .PARAMETER Port
        Specifies the TCP port number for the SMTP server connection. Common values are 25 (default), 587 (submission), or 465 (SMTPS).
        Defaults to 25 if not specified. Use port 587 for modern SMTP services like Office 365 or Gmail that require TLS encryption.

    .PARAMETER EnableSSL
        Enables SSL/TLS encryption for the SMTP connection to protect email content and credentials during transmission.
        Required for most cloud-based email services like Office 365, Gmail, and other providers that mandate encrypted connections.
        Use this with Port 587 or 465 for secure email delivery.

    .PARAMETER UseDefaultCredentials
        Configures the mail server to authenticate using the SQL Server Database Engine service account credentials (Windows Authentication).
        When enabled, SQL Server uses its own Windows identity to authenticate to the SMTP server instead of requiring a username and password.
        Useful in domain environments where the SQL Server service account has been granted relay permissions on the mail server.

    .PARAMETER UserName
        Specifies the username for SMTP server authentication when using Basic Authentication. Required by most cloud email providers.
        For Office 365, use the full email address (user@domain.com). For Gmail, use the email address or app-specific password username.
        Leave this parameter blank when using UseDefaultCredentials (Windows Authentication) or anonymous SMTP relay.

    .PARAMETER Password
        Specifies the password for SMTP server authentication as a SecureString when using Basic Authentication with the UserName parameter.
        For security, use Get-Credential to prompt for credentials or convert the password: ConvertTo-SecureString "password" -AsPlainText -Force.
        Not used when UseDefaultCredentials is enabled or when the SMTP server allows anonymous relay.

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

    .EXAMPLE
        PS C:\> $account = New-DbaDbMailAccount -SqlInstance sql2017 -Account 'The DBA Team' -EmailAddress admin@ad.local -MailServer smtp.ad.local

        Creates a new database mail account with the email address admin@ad.local on sql2017 named "The DBA Team" using the smtp.ad.local mail server.

    .EXAMPLE
        PS C:\> $params = @{
        >>     SqlInstance = 'sql2017'
        >>     Account     = 'Office365Alerts'
        >>     EmailAddress = 'alerts@company.com'
        >>     MailServer  = 'smtp.office365.com'
        >>     Port        = 587
        >>     EnableSSL   = $true
        >>     UserName    = 'alerts@company.com'
        >>     Password    = (ConvertTo-SecureString 'app-password' -AsPlainText -Force)
        >> }
        PS C:\> New-DbaDbMailAccount @params

        Creates a Database Mail account configured for Office 365 with TLS encryption on port 587 and Basic Authentication.

    .EXAMPLE
        PS C:\> $params = @{
        >>     SqlInstance            = 'sql2017'
        >>     Account                = 'InternalRelay'
        >>     EmailAddress           = 'sqlserver@company.local'
        >>     MailServer             = 'mail-relay.company.local'
        >>     UseDefaultCredentials  = $true
        >> }
        PS C:\> New-DbaDbMailAccount @params

        Creates a Database Mail account that uses Windows Authentication (SQL Server service account) to connect to an internal SMTP relay server.

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
        [int]$Port = 25,
        [switch]$EnableSSL,
        [switch]$UseDefaultCredentials,
        [string]$UserName,
        [securestring]$Password,
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
                    $mailServerObj = $accountObj.MailServers.Item($($server.DomainInstanceName))
                    $mailServerObj.Rename($MailServer)
                    $mailServerObj.Port = $Port
                    $mailServerObj.EnableSsl = $EnableSSL

                    if ($UseDefaultCredentials) {
                        $mailServerObj.UseDefaultCredentials = $true
                    } elseif ($UserName) {
                        $mailServerObj.SetAccount($UserName, $Password)
                    }

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