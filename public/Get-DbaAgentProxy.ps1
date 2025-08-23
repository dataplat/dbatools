function Get-DbaAgentProxy {
    <#
    .SYNOPSIS
        Retrieves SQL Server Agent proxy accounts and their associated credentials from target instances.

    .DESCRIPTION
        Retrieves SQL Server Agent proxy accounts which allow job steps to execute under different security contexts than the SQL Agent service account.
        This function is essential for security auditing, compliance reporting, and troubleshooting job step execution permissions.
        Returns detailed information including proxy names, associated credentials, descriptions, and enabled status across multiple SQL Server instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Proxy
        The name of the proxies to return. If null, will get all proxies from the server. Note - this parameter accepts wildcards.

    .PARAMETER ExcludeProxy
        The name of the proxies to exclude. If not provided, no proxies will be excluded. Note - this parameter accepts wildcards.


    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Proxy
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
        [string[]]$ExcludeProxy,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Getting Edition from $server"
            Write-Message -Level Verbose -Message "$server is a $($server.Edition)"

            if ($server.Edition -like 'Express*') {
                Stop-Function -Message "There is no SQL Agent on $server, it's a $($server.Edition)" -Continue
            }

            $defaults = "ComputerName", "SqlInstance", "InstanceName", "Name", "ID", "CredentialID", "CredentialIdentity", "CredentialName", "Description", "IsEnabled"

            $proxies = $server.Jobserver.ProxyAccounts

            if (Test-Bound 'Proxy') {
                $tempProxies = @()

                foreach ($a in $Proxy) {
                    $tempProxies += $proxies | Where-Object Name -like $a
                }

                $proxies = $tempProxies
            }

            if (Test-Bound 'ExcludeProxy') {
                foreach ($e in $ExcludeProxy) {
                    $proxies = $proxies | Where-Object Name -notlike $e
                }
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