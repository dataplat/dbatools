function Get-DbaClientProtocol {
    <#
        .SYNOPSIS
            Gets the SQL Server related client protocols on a computer.

        .DESCRIPTION
            Gets the SQL Server related client protocols on one or more computers.

            Requires Local Admin rights on destination computer(s).
            The client protocols can be enabled and disabled when retrieved via WSMan.

        .PARAMETER ComputerName
            The SQL Server (or server in general) that you're connecting to. This command handles named instances.

        .PARAMETER Credential
            Credential object used to connect to the computer as a different user.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Protocol
            Author: Klaas Vandenberghe ( @PowerDBAKlaas )

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaClientProtocol

        .EXAMPLE
            Get-DbaClientProtocol -ComputerName sqlserver2014a

            Gets the SQL Server related client protocols on computer sqlserver2014a.

        .EXAMPLE
            'sql1','sql2','sql3' | Get-DbaClientProtocol

            Gets the SQL Server related client protocols on computers sql1, sql2 and sql3.

        .EXAMPLE
            Get-DbaClientProtocol -ComputerName sql1,sql2 | Out-Gridview

            Gets the SQL Server related client protocols on computers sql1 and sql2, and shows them in a grid view.

        .EXAMPLE
            (Get-DbaClientProtocol -ComputerName sql2 | Where { $_.DisplayName = 'via' }).Disable()

            Disables the VIA ClientNetworkProtocol on computer sql2.
            If succesfull, returncode 0 is shown.
#>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential] $Credential,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ( $computer in $ComputerName.ComputerName ) {
            $server = Resolve-DbaNetworkName -ComputerName $computer -Credential $credential
            if ( $server.FullComputerName ) {
                $computer = $server.FullComputerName
                Write-Message -Level Verbose -Message "Getting SQL Server namespace on $computer" -EnableException $EnableException
                $namespace = Get-DbaCmObject -ComputerName $computer -Namespace root\Microsoft\SQLServer -Query "Select * FROM __NAMESPACE WHERE Name LIke 'ComputerManagement%'" -ErrorAction SilentlyContinue |
                    Where-Object {(Get-DbaCmObject -ComputerName $computer -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -ClassName ClientNetworkProtocol -ErrorAction SilentlyContinue).count -gt 0} |
                    Sort-Object Name -Descending | Select-Object -First 1

                if ( $namespace.Name ) {
                    Write-Message -Level Verbose -Message "Getting Cim class ClientNetworkProtocol in Namespace $($namespace.Name) on $computer" -EnableException $EnableException
                    try {
                        $prot = Get-DbaCmObject -ComputerName $computer -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -ClassName ClientNetworkProtocol -ErrorAction SilentlyContinue

                        $prot | Add-Member -Force -MemberType ScriptProperty -Name IsEnabled -Value { switch ( $this.ProtocolOrder ) { 0 { $false } default { $true } } }
                        $prot | Add-Member -Force -MemberType ScriptMethod -Name Enable -Value {Invoke-CimMethod -MethodName SetEnable -InputObject $this }
                        $prot | Add-Member -Force -MemberType ScriptMethod -Name Disable -Value {Invoke-CimMethod -MethodName SetDisable -InputObject $this }

                        foreach ( $protocol in $prot ) {
                            Select-DefaultView -InputObject $protocol -Property 'PSComputerName as ComputerName', 'ProtocolDisplayName as DisplayName', 'ProtocolDll as DLL', 'ProtocolOrder as Order', 'IsEnabled'
                        }
                    }
                    catch {
                        Write-Message -Level Warning -Message "No Sql ClientNetworkProtocol found on $computer" -EnableException $EnableException
                    }
                } #if namespace
                else {
                    Write-Message -Level Warning -Message "No ComputerManagement Namespace on $computer. Please note that this function is available from SQL 2005 up." -EnableException $EnableException
                } #else no namespace
            } #if computername
            else {
                Write-Message -Level Warning -Message "Failed to connect to $computer"
            }
        } #foreach computer
    }
}
