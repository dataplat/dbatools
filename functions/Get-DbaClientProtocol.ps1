function Get-DbaClientProtocol {
    <#
    .SYNOPSIS
        Gets the SQL Server related client protocols on a computer.

    .DESCRIPTION
        Gets the SQL Server related client protocols on one or more computers.

        Requires Local Admin rights on destination computer(s).
        The client protocols can be enabled and disabled when retrieved via WSMan.

    .PARAMETER ComputerName
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Server, Management
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaClientProtocol

    .EXAMPLE
        PS C:\> Get-DbaClientProtocol -ComputerName sqlserver2014a

        Gets the SQL Server related client protocols on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3' | Get-DbaClientProtocol

        Gets the SQL Server related client protocols on computers sql1, sql2 and sql3.

    .EXAMPLE
        PS C:\> Get-DbaClientProtocol -ComputerName sql1,sql2 | Out-GridView

        Gets the SQL Server related client protocols on computers sql1 and sql2, and shows them in a grid view.

    .EXAMPLE
        PS C:\> (Get-DbaClientProtocol -ComputerName sql2 | Where-Object { $_.DisplayName -eq 'Named Pipes' }).Disable()

        Disables the VIA ClientNetworkProtocol on computer sql2.
        If successful, return code 0 is shown.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential] $Credential,
        [switch]$EnableException
    )
    process {
        foreach ( $computer in $ComputerName.ComputerName ) {
            $server = Resolve-DbaNetworkName -ComputerName $computer -Credential $credential
            if ( $server.FullComputerName ) {
                $computer = $server.FullComputerName
                Write-Message -Level Verbose -Message "Getting SQL Server namespace on $computer"
                $namespace = Get-DbaCmObject -ComputerName $computer -Namespace root\Microsoft\SQLServer -Query "Select * FROM __NAMESPACE WHERE Name LIke 'ComputerManagement%'" -ErrorAction SilentlyContinue | Where-Object { (Get-DbaCmObject -ComputerName $computer -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -ClassName ClientNetworkProtocol -ErrorAction SilentlyContinue).count -gt 0 } | Sort-Object Name -Descending | Select-Object -First 1

                if ( $namespace.Name ) {
                    Write-Message -Level Verbose -Message "Getting Cim class ClientNetworkProtocol in Namespace $($namespace.Name) on $computer"
                    try {
                        $prot = Get-DbaCmObject -ComputerName $computer -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -ClassName ClientNetworkProtocol -ErrorAction SilentlyContinue

                        $prot | Add-Member -Force -MemberType ScriptProperty -Name IsEnabled -Value { switch ( $this.ProtocolOrder ) { 0 { $false } default { $true } } }
                        $prot | Add-Member -Force -MemberType ScriptMethod -Name Enable -Value { Invoke-CimMethod -MethodName SetEnable -InputObject $this }
                        $prot | Add-Member -Force -MemberType ScriptMethod -Name Disable -Value { Invoke-CimMethod -MethodName SetDisable -InputObject $this }

                        foreach ( $protocol in $prot ) {
                            Select-DefaultView -InputObject $protocol -Property 'PSComputerName as ComputerName', 'ProtocolDisplayName as DisplayName', 'ProtocolDll as DLL', 'ProtocolOrder as Order', 'IsEnabled'
                        }
                    } catch {
                        Write-Message -Level Warning -Message "No Sql ClientNetworkProtocol found on $computer"
                    }
                } else {
                    Write-Message -Level Warning -Message "No ComputerManagement Namespace on $computer. Please note that this function is available from SQL 2005 up."
                }
            } else {
                Write-Message -Level Warning -Message "Failed to connect to $computer"
            }
        }
    }
}