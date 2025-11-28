function Set-DbaDbMailAccount {
    <#
    .SYNOPSIS
        Modifies existing Database Mail account and mail server configurations on SQL Server instances

    .DESCRIPTION
        Modifies existing Database Mail account properties and mail server settings including SMTP server name, port numbers, SSL encryption, and authentication methods. This function allows DBAs to update Database Mail configurations for cloud email services like Office 365 or Gmail that require non-standard ports, TLS encryption, and authenticated connections. Use this to reconfigure mail accounts when changing email providers, updating credentials, or adjusting SMTP server settings.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Account
        Specifies the name of the Database Mail account to modify. This is the account name that was defined when the account was originally created.
        Use Get-DbaDbMailAccount to list available mail account names on an instance.

    .PARAMETER MailServer
        Specifies the name of the mail server configuration within the account to modify. Database Mail accounts can have multiple mail servers.
        If not specified and the account has only one mail server, that server will be modified. Use Get-DbaDbMailServer to list available mail servers.

    .PARAMETER NewMailServerName
        Renames the mail server to a new SMTP hostname or IP address. Use this when migrating to a different SMTP server.
        This changes the SMTP server that SQL Server connects to when sending emails through this account.

    .PARAMETER DisplayName
        Updates the friendly display name shown in the 'From' field of outgoing emails sent from this account.
        Recipients see this name instead of the raw account name or email address.

    .PARAMETER Description
        Updates the account description text that documents the account's purpose and usage.
        Useful for maintaining documentation about which jobs or applications use this account.

    .PARAMETER EmailAddress
        Updates the sender email address that appears in the 'From' field of outgoing messages from this Database Mail account.
        Must be a valid email address accepted by your SMTP server.

    .PARAMETER ReplyToAddress
        Updates the alternate email address for replies. When recipients reply to automated emails, responses go to this address.
        Useful when you want replies directed to a monitored mailbox rather than the automated sender address.

    .PARAMETER Port
        Updates the TCP port number for the SMTP server connection. Common values are 25 (default), 587 (submission), or 465 (SMTPS).
        Change this when migrating to cloud email services like Office 365 (port 587) or Gmail that require non-standard ports.

    .PARAMETER EnableSSL
        Enables or disables SSL/TLS encryption for the SMTP connection. Use -EnableSSL:$true to enable or -EnableSSL:$false to disable.
        Required for most cloud-based email services like Office 365, Gmail, and other providers that mandate encrypted connections.

    .PARAMETER UseDefaultCredentials
        Configures the mail server to use the SQL Server Database Engine service account credentials (Windows Authentication).
        Use -UseDefaultCredentials:$true to enable or -UseDefaultCredentials:$false to switch to Basic Authentication.

    .PARAMETER UserName
        Updates the username for SMTP server authentication when using Basic Authentication.
        For Office 365, use the full email address. For Gmail, use the email address or app-specific password username.
        Clear this when switching to UseDefaultCredentials (Windows Authentication).

    .PARAMETER Password
        Updates the password for SMTP server authentication as a SecureString when using Basic Authentication.
        For security, use Get-Credential or convert: ConvertTo-SecureString "password" -AsPlainText -Force.

    .PARAMETER InputObject
        Accepts Database Mail account objects from Get-DbaDbMailAccount via pipeline. Allows you to chain Database Mail operations together.

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

    .EXAMPLE
        PS C:\> Set-DbaDbMailAccount -SqlInstance sql2017 -Account 'The DBA Team' -Port 587 -EnableSSL

        Updates the mail server port to 587 and enables SSL for the 'The DBA Team' Database Mail account on sql2017.

    .EXAMPLE
        PS C:\> $params = @{
        >>     SqlInstance        = 'sql2017'
        >>     Account            = 'MaintenanceAlerts'
        >>     MailServer         = 'smtp.company.local'
        >>     NewMailServerName  = 'smtp.office365.com'
        >>     Port               = 587
        >>     EnableSSL          = $true
        >>     UserName           = 'alerts@company.com'
        >>     Password           = (Get-Credential -UserName 'alerts@company.com' -Message 'SMTP Password').Password
        >> }
        PS C:\> Set-DbaDbMailAccount @params

        Migrates an existing Database Mail account from an internal SMTP server to Office 365, updating the server name, port, enabling SSL, and configuring authentication.

    .EXAMPLE
        PS C:\> Get-DbaDbMailAccount -SqlInstance sql2017 -Account 'InternalRelay' | Set-DbaDbMailAccount -UseDefaultCredentials:$true

        Configures the 'InternalRelay' account to use Windows Authentication (SQL Server service account credentials) via pipeline input.

    .EXAMPLE
        PS C:\> $params = @{
        >>     SqlInstance  = 'sql2017'
        >>     Account      = 'Alerts'
        >>     MailServer   = 'old-smtp.company.com'
        >>     Port         = 25
        >>     EnableSSL    = $false
        >> }
        PS C:\> Set-DbaDbMailAccount @params

        Updates an existing mail server configuration to use port 25 without SSL encryption, useful for internal relay servers.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Account,
        [string]$MailServer,
        [string]$NewMailServerName,
        [string]$DisplayName,
        [string]$Description,
        [string]$EmailAddress,
        [string]$ReplyToAddress,
        [int]$Port,
        [bool]$EnableSSL,
        [bool]$UseDefaultCredentials,
        [string]$UserName,
        [securestring]$Password,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $accounts = @()
    }
    process {
        if ($SqlInstance) {
            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                $splatGetAccount = @{
                    SqlInstance = $server
                    Account     = $Account
                }
                $accounts += Get-DbaDbMailAccount @splatGetAccount
            }
        }

        foreach ($item in $InputObject) {
            $accounts += $item
        }
    }
    end {
        if (-not $accounts) {
            Stop-Function -Message "No Database Mail accounts to process"
            return
        }

        foreach ($accountObj in $accounts) {
            $server = $accountObj.Parent.Parent

            if ($Pscmdlet.ShouldProcess($server.DomainInstanceName, "Modifying Database Mail account '$($accountObj.Name)'")) {
                try {
                    $needsAccountAlter = $false

                    if (Test-Bound -ParameterName DisplayName) {
                        $accountObj.DisplayName = $DisplayName
                        $needsAccountAlter = $true
                    }

                    if (Test-Bound -ParameterName Description) {
                        $accountObj.Description = $Description
                        $needsAccountAlter = $true
                    }

                    if (Test-Bound -ParameterName EmailAddress) {
                        $accountObj.EmailAddress = $EmailAddress
                        $needsAccountAlter = $true
                    }

                    if (Test-Bound -ParameterName ReplyToAddress) {
                        $accountObj.ReplyToAddress = $ReplyToAddress
                        $needsAccountAlter = $true
                    }

                    if ($needsAccountAlter) {
                        $accountObj.Alter()
                    }

                    $mailServers = $accountObj.MailServers

                    if ($MailServer) {
                        $mailServerObj = $mailServers | Where-Object Name -eq $MailServer
                        if (-not $mailServerObj) {
                            Stop-Function -Message "Mail server '$MailServer' not found in account '$($accountObj.Name)' on $($server.DomainInstanceName)" -Continue
                        }
                    } elseif ($mailServers.Count -eq 1) {
                        $mailServerObj = $mailServers[0]
                    } else {
                        Stop-Function -Message "Account '$($accountObj.Name)' has multiple mail servers. Please specify -MailServer parameter" -Continue
                    }

                    $needsMailServerAlter = $false

                    if (Test-Bound -ParameterName NewMailServerName) {
                        $mailServerObj.Rename($NewMailServerName)
                        $needsMailServerAlter = $true
                    }

                    if (Test-Bound -ParameterName Port) {
                        $mailServerObj.Port = $Port
                        $needsMailServerAlter = $true
                    }

                    if (Test-Bound -ParameterName EnableSSL) {
                        $mailServerObj.EnableSsl = $EnableSSL
                        $needsMailServerAlter = $true
                    }

                    if (Test-Bound -ParameterName UseDefaultCredentials) {
                        $mailServerObj.UseDefaultCredentials = $UseDefaultCredentials
                        $needsMailServerAlter = $true
                    }

                    if (Test-Bound -ParameterName UserName) {
                        if (Test-Bound -ParameterName Password) {
                            $mailServerObj.SetAccount($UserName, $Password)
                        } else {
                            Stop-Function -Message "Password is required when setting UserName" -Continue
                        }
                        $needsMailServerAlter = $true
                    }

                    if ($needsMailServerAlter -or $needsAccountAlter) {
                        $accountObj.Alter()
                        $accountObj.Refresh()
                    }

                    Add-Member -Force -InputObject $accountObj -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $accountObj -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $accountObj -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    $accountObj | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, DisplayName, Description, EmailAddress, ReplyToAddress, IsBusyAccount, MailServers
                } catch {
                    Stop-Function -Message "Failure modifying Database Mail account '$($accountObj.Name)'" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}
