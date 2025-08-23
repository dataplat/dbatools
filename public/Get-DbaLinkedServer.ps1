function Get-DbaLinkedServer {
    <#
    .SYNOPSIS
        Retrieves linked server configurations and connection details from SQL Server instances.

    .DESCRIPTION
        Pulls complete linked server information from one or more SQL Server instances, including remote server names, authentication methods, and security settings. This helps DBAs audit cross-server connections for compliance reporting, troubleshoot connectivity issues, and document distributed database architectures. Returns details about the remote server, product type, impersonation settings, and login mappings for each configured linked server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LinkedServer
        Specifies one or more linked server names to retrieve information for. Accepts an array of server names for filtering results.
        Use this when you need details on specific linked servers instead of all configured linked servers on the instance.

    .PARAMETER ExcludeLinkedServer
        Specifies one or more linked server names to exclude from the results. Accepts an array of server names to filter out.
        Use this when you want to skip specific linked servers, such as excluding test or deprecated connections from your inventory.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: LinkedServer, Linked
        Author: Stephen Bennett, sqlnotesfromtheunderground.wordpress.com

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
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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