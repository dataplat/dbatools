function Get-DbaInstanceProtocol {
    <#
    .SYNOPSIS
        Gets the SQL Server related server protocols on a computer.

    .DESCRIPTION
        Gets the SQL Server related server protocols on one or more computers.

        Requires Local Admin rights on destination computer(s).
        The server protocols can be enabled and disabled when retrieved via WSMan.

    .PARAMETER ComputerName
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Server, Management, Protocol
        Author: Klaas Vandenberghe ( @PowerDBAKlaas )

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaInstanceProtocol

    .EXAMPLE
        PS C:\> Get-DbaInstanceProtocol -ComputerName sqlserver2014a

        Gets the SQL Server related server protocols on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3' | Get-DbaInstanceProtocol

        Gets the SQL Server related server protocols on computers sql1, sql2 and sql3.

    .EXAMPLE
        PS C:\> Get-DbaInstanceProtocol -ComputerName sql1,sql2

        Gets the SQL Server related server protocols on computers sql1 and sql2.

    .EXAMPLE
        PS C:\> (Get-DbaInstanceProtocol -ComputerName sql1 | Where-Object { $_.DisplayName -eq 'Named Pipes' }).Disable()

        Disables the VIA ServerNetworkProtocol on computer sql1.
        If successful, return code 0 is shown.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {
        foreach ($Computer in $ComputerName.ComputerName) {
            $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
            if ($Server.FullComputerName) {
                $Computer = $server.FullComputerName
                Write-Message -Level Verbose -Message "Getting SQL Server namespace on $computer"
                $namespace = Get-DbaCmObject -ComputerName $Computer -NameSpace root\Microsoft\SQLServer -Query "Select * FROM __NAMESPACE WHERE Name Like 'ComputerManagement%'" -ErrorAction SilentlyContinue | Where-Object { (Get-DbaCmObject -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -ClassName ServerNetworkProtocol -ErrorAction SilentlyContinue).count -gt 0 } | Sort-Object Name -Descending | Select-Object -First 1
                if ($namespace.Name) {
                    Write-Message -Level Verbose -Message "Getting Cim class ServerNetworkProtocol in Namespace $($namespace.Name) on $Computer"
                    try {
                        $prot = Get-DbaCmObject -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -ClassName ServerNetworkProtocol -ErrorAction SilentlyContinue
                        $prot | Add-Member -Force -MemberType ScriptMethod -Name Enable -Value { Invoke-CimMethod -MethodName SetEnable -InputObject $this }
                        $prot | Add-Member -Force -MemberType ScriptMethod -Name Disable -Value { Invoke-CimMethod -MethodName SetDisable -InputObject $this }
                        foreach ($protocol in $prot) { Select-DefaultView -InputObject $protocol -Property 'PSComputerName as ComputerName', 'InstanceName', 'ProtocolDisplayName as DisplayName', 'ProtocolName as Name', 'MultiIpconfigurationSupport as MultiIP', 'Enabled as IsEnabled' }
                    } catch {
                        Write-Message -Level Warning -Message "No Sql ServerNetworkProtocol found on $Computer"
                    }
                } else {
                    Write-Message -Level Warning -Message "No ComputerManagement Namespace on $Computer. Please note that this function is available from SQL 2005 up."
                }
            } else {
                Write-Message -Level Warning -Message "Failed to connect to $Computer"
            }
        }
    }
}