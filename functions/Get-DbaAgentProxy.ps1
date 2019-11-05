function Get-DbaAgentProxy {
    <#
    .SYNOPSIS
        Returns all SQL Agent proxies on a SQL Server Agent.

    .DESCRIPTION
        This function returns SQL Agent proxies.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Proxy
        The proxy to process - this list is auto-populated from the server. If unspecified, all proxies will be processed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, SMO
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentProxy

    .EXAMPLE
        PS C:\> Get-DbaAgentProxy -SqlInstance ServerA,ServerB\instanceB

        Returns all SQL Agent proxies on serverA and serverB\instanceB

    .EXAMPLE
        PS C:\> 'serverA','serverB\instanceB' | Get-DbaAgentProxy

        Returns all SQL Agent proxies  on serverA and serverB\instanceB

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Proxy,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Getting Edition from $server"
            Write-Message -Level Verbose -Message "$server is a $($server.Edition)"

            if ($server.Edition -like 'Express*') {
                Stop-Function -Message "There is no SQL Agent on $server, it's a $($server.Edition)" -Continue
            }

            $defaults = "ComputerName", "SqlInstance", "InstanceName", "Name", "ID", "CredentialID", "CredentialIdentity", "CredentialName", "Description", "IsEnabled"

            $proxies = $server.Jobserver.ProxyAccounts

            if ($proxy) {
                $proxies = $proxies | Where-Object Name -In $proxy
            }

            foreach ($px in $proxies) {
                Add-Member -Force -InputObject $px -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $px -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $px -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Select-DefaultView -InputObject $px -Property $defaults
            }
        }
    }
}