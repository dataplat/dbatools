function Get-DbaDbMailAccount {
    <#
    .SYNOPSIS
        Retrieves Database Mail account configurations from SQL Server instances

    .DESCRIPTION
        Retrieves Database Mail account configurations including email addresses, display names, SMTP server settings, and authentication details from SQL Server instances. This function helps DBAs audit email configurations across their environment, troubleshoot mail delivery issues, and document Database Mail settings for compliance or migration purposes. The returned account objects include connection details, server configurations, and account properties that can be used to verify proper Database Mail setup.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Account
        Specifies one or more Database Mail account names to retrieve. Accepts exact account names and supports multiple values.
        Use this when you need to check specific mail accounts rather than retrieving all configured accounts on the instance.

    .PARAMETER ExcludeAccount
        Specifies one or more Database Mail account names to exclude from results. Accepts exact account names and supports multiple values.
        Use this when you want to retrieve most accounts but skip specific ones, such as excluding test or deprecated accounts from auditing reports.

    .PARAMETER InputObject
        Accepts SqlMail objects from the pipeline, typically from Get-DbaDbMail. Allows you to chain Database Mail commands together.
        Use this when processing multiple instances through Get-DbaDbMail or when working with previously retrieved Database Mail configurations.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Mail, DbMail, Email
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbMailAccount

    .EXAMPLE
        PS C:\> Get-DbaDbMailAccount -SqlInstance sql01\sharepoint

        Returns Database Mail accounts on sql01\sharepoint.

    .EXAMPLE
        PS C:\> Get-DbaDbMailAccount -SqlInstance sql01\sharepoint -Account 'The DBA Team'

        Returns 'The DBA Team' Database Mail account from sql01\sharepoint.

    .EXAMPLE
        PS C:\> Get-DbaDbMailAccount -SqlInstance sql01\sharepoint | Select-Object *

        Returns the Database Mail accounts on sql01\sharepoint then return a bunch more columns.

    .EXAMPLE
        PS C:\> $servers = sql2014, sql2016, sqlcluster\sharepoint
        PS C:\> $servers | Get-DbaDbMail | Get-DbaDbMailAccount

        Returns the Database Mail accounts for sql2014, sql2016 and sqlcluster\sharepoint.

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Account,
        [string[]]$ExcludeAccount,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Mail.SqlMail[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDbMail -SqlInstance $instance -SqlCredential $SqlCredential
        }

        if (-not $InputObject) {
            Stop-Function -Message "No servers to process"
            return
        }

        foreach ($mailserver in $InputObject) {
            try {
                $accounts = $mailserver.Accounts

                if ($Account) {
                    $accounts = $accounts | Where-Object Name -in $Account
                }

                If ($ExcludeAccount) {
                    $accounts = $accounts | Where-Object Name -notin $ExcludeAccount
                }

                $accounts | Add-Member -Force -MemberType NoteProperty -Name ComputerName -value $mailserver.ComputerName
                $accounts | Add-Member -Force -MemberType NoteProperty -Name InstanceName -value $mailserver.InstanceName
                $accounts | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -value $mailserver.SqlInstance
                $accounts | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, ID, Name, DisplayName, Description, EmailAddress, ReplyToAddress, IsBusyAccount, MailServers
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}