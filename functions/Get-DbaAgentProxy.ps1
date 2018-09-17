function Get-DbaAgentProxy {
    <#
        .SYNOPSIS
            Returns all SQL Agent proxies on a SQL Server Agent.

        .DESCRIPTION
            This function returns SQL Agent proxies.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Chrissy LeMaire ( @cl )
            Tags: Agent, SMO
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaAgentProxy

        .EXAMPLE
            Get-DbaAgentProxy -SqlInstance ServerA,ServerB\instanceB
            Returns all SQL Agent proxies on serverA and serverB\instanceB

        .EXAMPLE
            'serverA','serverB\instanceB' | Get-DbaAgentProxy
            Returns all SQL Agent proxies  on serverA and serverB\instanceB
    #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "Instance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            
            Write-Message -Level Verbose -Message "Getting Edition from $server"
            Write-Message -Level Verbose -Message "$server is a $($server.Edition)"
            
            if ($server.Edition -like 'Express*') {
                Stop-Function -Message "There is no SQL Agent on $server, it's a $($server.Edition)" -Continue
            }
            
            $defaults = "ComputerName", "SqlInstance", "InstanceName", "Name", "ID", "CredentialID", "CredentialIdentity", "CredentialName", "Description", "IsEnabled"
            
            $proxies = $server.Jobserver.ProxyAccounts
            
            foreach ($proxy in $proxies) {
                Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $proxy -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Select-DefaultView -InputObject $proxy -Property $defaults
            }
        }
    }
}