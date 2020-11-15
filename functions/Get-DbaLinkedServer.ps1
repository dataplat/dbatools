function Get-DbaLinkedServer {
    <#
    .SYNOPSIS
        Gets all linked servers and a summary of information from the linked servers listed.

    .DESCRIPTION
        Retrieves information about each linked server on the instance(s).

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LinkedServer
        The linked server(s) to process - this list is auto-populated from the server. If unspecified, all linked servers will be processed.

    .PARAMETER ExcludeLinkedServer
        The linked server(s) to exclude - this list is auto-populated from the server

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: LinkedServer, Linked
        Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaLinkedServer

    .EXAMPLE
        PS C:\> Get-DbaLinkedServer -SqlInstance DEV01

        Returns all linked servers for the SQL Server instance DEV01

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance DEV01 -Group SQLDEV | Get-DbaLinkedServer | Out-GridView

        Returns all linked servers for a group of servers from SQL Server Central Management Server (CMS). Send output to GridView.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$LinkedServer,
        [object[]]$ExcludeLinkedServer,
        [switch]$EnableException
    )
    process {
        foreach ($Instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $lservers = $server.LinkedServers

            if ($LinkedServer) {
                $lservers = $lservers | Where-Object { $_.Name -in $LinkedServer }
            }
            if ($ExcludeLinkedServer) {
                $lservers = $lservers | Where-Object { $_.Name -notin $ExcludeLinkedServer }
            }

            foreach ($ls in $lservers) {
                Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name Impersonate -value $ls.LinkedServerLogins.Impersonate
                Add-Member -Force -InputObject $ls -MemberType NoteProperty -Name RemoteUser -value $ls.LinkedServerLogins.RemoteUser

                Select-DefaultView -InputObject $ls -Property ComputerName, InstanceName, SqlInstance, Name, 'DataSource as RemoteServer', ProductName, Impersonate, RemoteUser, 'DistPublisher as Publisher', Distributor, DateLastModified
            }
        }
    }
}