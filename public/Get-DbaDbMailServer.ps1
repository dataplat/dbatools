function Get-DbaDbMailServer {
    <#
    .SYNOPSIS
        Retrieves SMTP server configurations from SQL Server Database Mail accounts

    .DESCRIPTION
        Retrieves detailed SMTP server configuration information from all Database Mail accounts on SQL Server instances. This function pulls the actual mail server settings including port numbers, SSL configuration, authentication methods, and connection details. Useful for auditing email infrastructure, troubleshooting delivery issues, and documenting Database Mail configurations across your environment.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Server
        Specifies one or more SMTP server names to retrieve from Database Mail accounts. Use this when you need to check configuration for specific mail servers rather than all configured servers.
        Accepts exact server names like 'smtp.company.com' or 'mail-relay-01'.

    .PARAMETER Account
        Restricts results to mail servers associated with specific Database Mail account names. Use this when troubleshooting email issues for particular applications or services.
        Helpful for isolating server configurations when you have multiple Database Mail accounts with different SMTP settings.

    .PARAMETER InputObject
        Accepts Database Mail objects from Get-DbaDbMail via pipeline. Allows you to chain Database Mail operations together.
        Use this when you need to process mail server configurations from a filtered set of SQL instances or specific Database Mail setups.

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
        https://dbatools.io/Get-DbaDbMailServer

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Mail.MailServer

        Returns one or more Database Mail server objects from configured Database Mail accounts. Each server object represents an SMTP server configuration associated with a Database Mail account.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Account: The name of the Database Mail account that uses this server
        - Name: The name or hostname of the SMTP server
        - Port: The SMTP port number used for connections (typically 25, 465, or 587)
        - EnableSsl: Boolean indicating whether SSL/TLS encryption is enabled for this server
        - ServerType: The type of mail server (typically "SMTP")
        - UserName: The username used to authenticate with the SMTP server, if required
        - UseDefaultCredentials: Boolean indicating whether default Windows credentials are used
        - NoCredentialChange: Boolean indicating the credential policy for the server

        All properties from the SMO MailServer object are accessible via Select-Object * if needed.

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
        if ($SqlInstance) {
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
                    $servers | Add-Member -Force -MemberType NoteProperty -Name Account -value $servers.Parent.Name
                    $servers | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Account, Name, Port, EnableSsl, ServerType, UserName, UseDefaultCredentials, NoCredentialChange
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}