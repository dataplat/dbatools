function Get-DbaDbMailServer {
    <#
    .SYNOPSIS
        Gets database mail servers from SQL Server

    .DESCRIPTION
        Gets database mail servers from SQL Server

    .PARAMETER SqlInstance
        TThe target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Server
        Specifies one or more server(s) to get. If unspecified, all servers will be returned.

    .PARAMETER Account
        Get only the mail server associated with specific accounts

    .PARAMETER InputObject
        Accepts pipeline input from Get-DbaDbMail

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DatabaseMail, DBMail, Mail
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbMailServer

    .EXAMPLE
        PS C:\> Get-DbaDbMailServer -SqlInstance sql01\sharepoint

        Returns all DBMail servers on sql01\sharepoint

    .EXAMPLE
        PS C:\> Get-DbaDbMailServer -SqlInstance sql01\sharepoint -Server DbaTeam

        Returns The DBA Team DBMail server from sql01\sharepoint

    .EXAMPLE
        PS C:\> Get-DbaDbMailServer -SqlInstance sql01\sharepoint | Select-Object *

        Returns the DBMail servers on sql01\sharepoint then return a bunch more columns

    .EXAMPLE
        PS C:\> $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
        PS C:\> $servers | Get-DbaDbMail | Get-DbaDbMailServer

        Returns the DBMail servers for "sql2014","sql2016" and "sqlcluster\sharepoint"

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Name")]
        [string[]]$Server,
        [string[]]$Account,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Mail.SqlMail[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDbMail -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }

        if (-not $InputObject) {
            Stop-Function -Message "No servers to process"
            return
        }

        foreach ($mailserver in $InputObject) {
            try {
                $accounts = $mailserver | Get-DbaDbMailAccount -Account $Account
                $servers = $accounts.MailServers

                if ($Server) {
                    $servers = $servers | Where-Object Name -in $Server
                }

                if ($servers) {
                    $servers | Add-Member -Force -MemberType NoteProperty -Name ComputerName -value $mailserver.ComputerName
                    $servers | Add-Member -Force -MemberType NoteProperty -Name InstanceName -value $mailserver.InstanceName
                    $servers | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -value $mailserver.SqlInstance
                    $servers | Add-Member -Force -MemberType NoteProperty -Name Account -value $servers[0].Parent.Name
                    $servers | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Account, Name, Port, EnableSsl, ServerType, UserName, UseDefaultCredentials, NoCredentialChange
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}