function Get-DbaDbMail {
    <#
    .SYNOPSIS
        Retrieves Database Mail configuration including profiles, accounts, and settings from SQL Server instances

    .DESCRIPTION
        Retrieves the complete Database Mail configuration from one or more SQL Server instances, including mail profiles, SMTP accounts, configuration values, and properties. This function provides a quick way to audit your email setup across multiple servers, troubleshoot mail delivery issues, or document your Database Mail configuration for compliance purposes. The output includes server identification details to help when working with multiple instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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
        https://dbatools.io/Get-DbaDbMail

    .EXAMPLE
        PS C:\> Get-DbaDbMail -SqlInstance sql01\sharepoint

        Returns the db mail server object on sql01\sharepoint

    .EXAMPLE
        PS C:\> Get-DbaDbMail -SqlInstance sql01\sharepoint | Select-Object *

        Returns the db mail server object on sql01\sharepoint then return a bunch more columns

    .EXAMPLE
        PS C:\> $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
        PS C:\> $servers | Get-DbaDbMail

        Returns the db mail server object for "sql2014","sql2016" and "sqlcluster\sharepoint"

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $mailserver = $server.Mail
                Add-Member -Force -InputObject $mailserver -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $mailserver -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $mailserver -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                $mailserver | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Profiles, Accounts, ConfigurationValues, Properties
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}