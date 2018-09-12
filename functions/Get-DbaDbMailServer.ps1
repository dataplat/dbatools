function Get-DbaDbMailServer {
    <#
    .SYNOPSIS
        Gets database mail servers from SQL Server

    .DESCRIPTION
        Gets database mail servers from SQL Server

    .PARAMETER SqlInstance
        The SQL Server instance, or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
        Tags: databasemail, dbmail, mail
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbMailServer

    .EXAMPLE
        Get-DbaDbMailServer -SqlInstance sql01\sharepoint

        Returns dbmail servers on sql01\sharepoint

    .EXAMPLE
        Get-DbaDbMailServer -SqlInstance sql01\sharepoint -Name ProhibitedExtensions

        Returns The DBA Team dbmail server from sql01\sharepoint
    
    .EXAMPLE
        Get-DbaDbMailServer -SqlInstance sql01\sharepoint | Select *

        Returns the dbmail servers on sql01\sharepoint then return a bunch more columns

    .EXAMPLE
        $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
        $servers | Get-DbaDbMail | Get-DbaDbMailServer

       Returns the db dbmail servers for "sql2014","sql2016" and "sqlcluster\sharepoint"

#>
    [CmdletBinding()]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
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
            Write-Message -Level Verbose -Message "Connecting to $instance"
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
                                
                $servers | Add-Member -Force -MemberType NoteProperty -Name ComputerName -value $mailserver.ComputerName
                $servers | Add-Member -Force -MemberType NoteProperty -Name InstanceName -value $mailserver.InstanceName
                $servers | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -value $mailserver.SqlInstance
                $servers | Add-Member -Force -MemberType NoteProperty -Name Account -value $servers[0].Parent.Name
                $servers | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Account, Name, Port, EnableSsl, ServerType, UserName, UseDefaultCredentials, NoCredentialChange
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}