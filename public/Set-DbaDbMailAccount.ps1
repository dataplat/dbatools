function Set-DbaDbMailAccount {
    <#
    .SYNOPSIS
        Modifies an existing Database Mail account on SQL Server

    .DESCRIPTION
        Modifies the configuration of an existing Database Mail account including account properties (display name, email address, description) and mail server settings (SMTP server name, port, SSL, and authentication). This command is useful for updating Database Mail accounts to use cloud email services like Office 365 or Gmail, or for updating credentials when passwords change.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Account
        Specifies one or more Database Mail account names to modify. Used in combination with -SqlInstance.

    .PARAMETER InputObject
        Accepts MailAccount objects from the pipeline, typically from Get-DbaDbMailAccount. Allows you to chain Database Mail commands together.

    .PARAMETER DisplayName
        Updates the friendly name that appears in the 'From' field of outgoing emails.

    .PARAMETER Description
        Updates the optional documentation text describing the account's purpose and usage.

    .PARAMETER EmailAddress
        Updates the sender email address that appears in outgoing messages from this Database Mail account.

    .PARAMETER ReplyToAddress
        Updates the alternate email address for replies when different from the sender address.

    .PARAMETER NewMailServerName
        Renames or replaces the SMTP server hostname for the mail account. Use this to migrate to a different SMTP server.

    .PARAMETER Port
        Updates the TCP port number used to connect to the SMTP server. Common values are 25 (standard SMTP), 465 (SMTPS), and 587 (SMTP with STARTTLS).
        Use 587 for Office 365 and Gmail which require STARTTLS.

    .PARAMETER EnableSSL
        Enables or disables SSL/TLS encryption for the SMTP connection. Use -EnableSSL:$false to explicitly disable SSL.

    .PARAMETER UseDefaultCredentials
        Enables or disables Windows integrated authentication (the SQL Server service account credentials) for SMTP authentication.
        Use -UseDefaultCredentials:$false to explicitly disable Windows authentication.

    .PARAMETER UserName
        Updates the username for SMTP authentication. For Office 365, use the full email address.

    .PARAMETER Password
        Updates the password for SMTP authentication as a SecureString.
        Create with: ConvertTo-SecureString 'yourpassword' -AsPlainText -Force

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DatabaseMail, DbMail, Mail
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbMailAccount

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Mail.MailAccount

        Returns the updated MailAccount object from the specified SQL Server instance.

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

    .EXAMPLE
        PS C:\> Set-DbaDbMailAccount -SqlInstance sql2017 -Account 'MaintenanceAlerts' -Port 587 -EnableSSL

        Updates the MaintenanceAlerts mail account on sql2017 to use port 587 with SSL enabled.

    .EXAMPLE
        PS C:\> $splatAccount = @{
        >>     SqlInstance       = 'sql2017'
        >>     Account           = 'Alerts'
        >>     NewMailServerName = 'smtp.office365.com'
        >>     Port              = 587
        >>     EnableSSL         = $true
        >>     UserName          = 'alerts@company.com'
        >>     Password          = (ConvertTo-SecureString 'app-password' -AsPlainText -Force)
        >> }
        PS C:\> Set-DbaDbMailAccount @splatAccount

        Migrates the Alerts mail account on sql2017 to Office 365 with SSL and basic authentication.

    .EXAMPLE
        PS C:\> Get-DbaDbMailAccount -SqlInstance sql2017 -Account 'MaintenanceAlerts' | Set-DbaDbMailAccount -Port 25 -EnableSSL:$false

        Uses the pipeline to update the MaintenanceAlerts account to use port 25 with SSL disabled.

    .EXAMPLE
        PS C:\> Set-DbaDbMailAccount -SqlInstance sql2017 -Account 'DomainRelay' -UseDefaultCredentials

        Configures the DomainRelay mail account to use Windows integrated authentication.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Account,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Mail.MailAccount[]]$InputObject,
        [string]$DisplayName,
        [string]$Description,
        [string]$EmailAddress,
        [string]$ReplyToAddress,
        [string]$NewMailServerName,
        [int]$Port,
        [switch]$EnableSSL,
        [switch]$UseDefaultCredentials,
        [string]$UserName,
        [System.Security.SecureString]$Password,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDbMailAccount -SqlInstance $instance -SqlCredential $SqlCredential -Account $Account -EnableException:$EnableException
        }

        foreach ($mailAccount in $InputObject) {
            $instanceName = $mailAccount.SqlInstance
            if (-not $instanceName) {
                $instanceName = $mailAccount.Parent.Parent.DomainInstanceName
            }

            if ($Pscmdlet.ShouldProcess($instanceName, "Updating mail account $($mailAccount.Name)")) {
                $accountChanged = $false

                try {
                    if (Test-Bound -ParameterName DisplayName) { $mailAccount.DisplayName = $DisplayName; $accountChanged = $true }
                    if (Test-Bound -ParameterName Description) { $mailAccount.Description = $Description; $accountChanged = $true }
                    if (Test-Bound -ParameterName EmailAddress) { $mailAccount.EmailAddress = $EmailAddress; $accountChanged = $true }
                    if (Test-Bound -ParameterName ReplyToAddress) { $mailAccount.ReplyToAddress = $ReplyToAddress; $accountChanged = $true }

                    if ($accountChanged) {
                        $mailAccount.Alter()
                    }
                } catch {
                    Stop-Function -Message "Failure updating account properties for $($mailAccount.Name) on $instanceName" -Target $mailAccount -ErrorRecord $_ -Continue
                }

                try {
                    $mailServerObj = $mailAccount.MailServers | Select-Object -First 1

                    if ($null -ne $mailServerObj) {
                        if (Test-Bound -ParameterName NewMailServerName) { $mailServerObj.Rename($NewMailServerName) }
                        if (Test-Bound -ParameterName Port) { $mailServerObj.Port = $Port }
                        if (Test-Bound -ParameterName EnableSSL) { $mailServerObj.EnableSsl = $EnableSSL.IsPresent }
                        if (Test-Bound -ParameterName UseDefaultCredentials) { $mailServerObj.UseDefaultCredentials = $UseDefaultCredentials.IsPresent }
                        if (Test-Bound -ParameterName UserName) { $mailServerObj.UserName = $UserName }
                        if (Test-Bound -ParameterName Password) {
                            $mailServerObj.Password = (New-Object System.Net.NetworkCredential("", $Password)).Password
                        }
                        $mailServerObj.Alter()
                    }
                } catch {
                    Stop-Function -Message "Failure updating mail server for account $($mailAccount.Name) on $instanceName" -Target $mailAccount -ErrorRecord $_ -Continue
                }

                $mailAccount.Refresh()
                Add-Member -Force -InputObject $mailAccount -MemberType NoteProperty -Name ComputerName -value $mailAccount.Parent.Parent.ComputerName
                Add-Member -Force -InputObject $mailAccount -MemberType NoteProperty -Name InstanceName -value $mailAccount.Parent.Parent.ServiceName
                Add-Member -Force -InputObject $mailAccount -MemberType NoteProperty -Name SqlInstance -value $mailAccount.Parent.Parent.DomainInstanceName
                $mailAccount | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, DisplayName, Description, EmailAddress, ReplyToAddress, IsBusyAccount, MailServers
            }
        }
    }
}
