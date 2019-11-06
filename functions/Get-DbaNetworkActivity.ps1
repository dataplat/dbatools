function Get-DbaNetworkActivity {
    <#
    .SYNOPSIS
        Gets the Current traffic on every Network Interface on a computer.

    .DESCRIPTION
        Gets the Current traffic on every Network Interface on a computer.
        See https://msdn.microsoft.com/en-us/library/aa394293(v=vs.85).aspx

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Server, Management, Network
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaNetworkActivity

    .EXAMPLE
        PS C:\> Get-DbaNetworkActivity -ComputerName sqlserver2014a

        Gets the Current traffic on every Network Interface on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3' | Get-DbaNetworkActivity

        Gets the Current traffic on every Network Interface on computers sql1, sql2 and sql3.

    .EXAMPLE
        PS C:\> Get-DbaNetworkActivity -ComputerName sql1,sql2

        Gets the Current traffic on every Network Interface on computers sql1 and sql2.
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [string[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential] $Credential,
        [switch]$EnableException
    )

    begin {
        $ComputerName = $ComputerName | ForEach-Object { $_.split("\")[0] } | Select-Object -Unique
        $sessionoption = New-CimSessionOption -Protocol DCom
    }
    process {
        foreach ($computer in $ComputerName) {
            $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
            if ( $Server.FullComputerName ) {
                $Computer = $server.FullComputerName
                Write-Message -Level Verbose -Message "Creating CIMSession on $computer over WSMan"
                $CIMsession = New-CimSession -ComputerName $Computer -ErrorAction SilentlyContinue -Credential $Credential
                if ( -not $CIMSession ) {
                    Write-Message -Level Verbose -Message "Creating CIMSession on $computer over WSMan failed. Creating CIMSession on $computer over DCom"
                    $CIMsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
                }
                if ( $CIMSession ) {
                    Write-Message -Level Verbose -Message "Getting properties for Network Interfaces on $computer"
                    $NICs = Get-CimInstance -CimSession $CIMSession -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface
                    $NICs | Add-Member -Force -MemberType ScriptProperty -Name ComputerName -Value { $computer }
                    $NICs | Add-Member -Force -MemberType ScriptProperty -Name Bandwith -Value { switch ( $this.CurrentBandWidth ) { 10000000000 { '10Gb' } 1000000000 { '1Gb' } 100000000 { '100Mb' } 10000000 { '10Mb' } 1000000 { '1Mb' } 100000 { '100Kb' } default { 'Low' } } }
                    foreach ( $NIC in $NICs ) { Select-DefaultView -InputObject $NIC -Property 'ComputerName', 'Name as NIC', 'BytesReceivedPersec', 'BytesSentPersec', 'BytesTotalPersec', 'Bandwidth' }
                } #if CIMSession
                else {
                    Write-Message -Level Warning -Message "Can't create CIMSession on $computer"
                }
            } #if computername
            else {
                Write-Message -Level Warning -Message "can't connect to $computer"
            }
        } #foreach computer
    } #PROCESS
} #function