function Get-DbaMsdtc {
    <#
    .SYNOPSIS
        Retrieves Microsoft Distributed Transaction Coordinator (MSDTC) service status and configuration details

    .DESCRIPTION
        Returns comprehensive MSDTC information including service state, security settings, and component identifiers (CIDs) from target servers. MSDTC is essential for SQL Server distributed transactions, linked server operations, and cross-database transactions that span multiple servers or instances.

        This function helps DBAs troubleshoot distributed transaction failures, verify MSDTC configuration for linked servers, and audit security settings across multiple servers. It queries both the Windows service status and registry settings to provide a complete picture of the MSDTC configuration.

        Requires: Windows administrator access on target servers

    .PARAMETER ComputerName
        The target computer.

    .PARAMETER Credential
        Alternative credential

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Msdtc, dtc, General
        Author: Klaas Vandenberghe (@powerdbaklaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaMsdtc

    .EXAMPLE
        PS C:\> Get-DbaMsdtc -ComputerName srv0042

        Get DTC status for the server srv0042

    .EXAMPLE
        PS C:\> $Computers = (Get-Content D:\configfiles\SQL\MySQLInstances.txt | % {$_.split('\')[0]})
        PS C:\> $Computers | Get-DbaMsdtc

        Get DTC status for all the computers in a .txt file

    .EXAMPLE
        PS C:\> Get-DbaMsdtc -Computername $Computers | Where-Object { $_.dtcservicestate -ne 'running' }

        Get DTC status for all the computers where the MSDTC Service is not running

    .EXAMPLE
        PS C:\> Get-DbaMsdtc -ComputerName srv0042 | Out-Gridview

        Get DTC status for the computer srv0042 and show in a grid view

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [Alias('cn', 'host', 'Server')]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )

    begin {
        $query = "Select * FROM Win32_Service WHERE Name = 'MSDTC'"
        $dtcSecurity = {
            Get-ItemProperty -Path HKLM:\Software\Microsoft\MSDTC\Security |
                Select-Object PSPath, PSComputerName, AccountName, networkDTCAccess,
                networkDTCAccessAdmin, networkDTCAccessClients, networkDTCAccessInbound,
                networkDTCAccessOutBound, networkDTCAccessTip, networkDTCAccessTransactions, XATransactions
        }
        $dtcCids = {
            New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT | Out-Null
            Get-ItemProperty -Path HKCR:\CID\*\Description |
                Select-Object @{ l = 'Data'; e = { $_.'(default)' } }, @{ l = 'CID'; e = { $_.PSParentPath.split('\')[-1] } }
            Remove-PSDrive -Name HKCR | Out-Null
        }
    }
    process {
        foreach ($computer in $ComputerName.ComputerName) {
            $reg = $cids = $null
            $cidHash = @{ }
            if ($Credential) {
                $result = Test-PSRemoting -ComputerName $computer -Credential $Credential
            } else {
                $result = Test-PSRemoting -ComputerName $computer
            }
            if ($result) {
                $dtcservice = $null
                Write-Message -Level Verbose -Message "Getting DTC on $computer via WSMan"
                $dtcservice = Get-CimInstance -ComputerName $computer -Query $query
                if ( $null -eq $dtcservice ) {
                    Write-Message -Level Warning -Message "Can't connect to CIM on $computer via WSMan"
                }

                Write-Message -Level Verbose -Message "Getting MSDTC Security Registry Values on $computer"
                try {
                    $reg = Invoke-Command2 -ComputerName $computer -ScriptBlock $dtcSecurity -Credential $Credential
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
                if ( $null -eq $reg ) {
                    Write-Message -Level Warning -Message "Can't connect to MSDTC Security registry on $computer"
                }
                Write-Message -Level Verbose -Message "Getting MSDTC CID Registry Values on $computer"
                try {
                    $cids = Invoke-Command2 -ComputerName $computer -ScriptBlock $dtcCids -Credential $Credential
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
                if ( $null -ne $cids ) {
                    foreach ($key in $cids) {
                        $cidHash.Add($key.Data, $key.CID)
                    }
                } else {
                    Write-Message -Level Warning -Message "Can't connect to MSDTC CID registry on $computer"
                }
            } else {
                Write-Message -Level Verbose -Message "PSRemoting is not enabled on $computer"
                try {
                    Write-Message -Level Verbose -Message "Failed To get DTC via WinRM. Getting DTC on $computer via DCom"
                    $SessionParams = @{ }
                    $SessionParams.ComputerName = $Computer
                    $SessionParams.SessionOption = (New-CimSessionOption -Protocol Dcom)
                    $Session = New-CimSession @SessionParams
                    $dtcservice = Get-CimInstance -CimSession $Session -Query $query
                } catch {
                    Stop-Function -Message "Can't connect to CIM on $computer via DCom" -Target $computer -ErrorRecord $_ -Continue
                }
            }
            if ( $dtcservice ) {
                [PSCustomObject]@{
                    ComputerName                 = $dtcservice.PSComputerName
                    DTCServiceName               = $dtcservice.DisplayName
                    DTCServiceState              = $dtcservice.State
                    DTCServiceStatus             = $dtcservice.Status
                    DTCServiceStartMode          = $dtcservice.StartMode
                    DTCServiceAccount            = $dtcservice.StartName
                    DTCCID_MSDTC                 = $cidHash['MSDTC']
                    DTCCID_MSDTCUIS              = $cidHash['MSDTCUIS']
                    DTCCID_MSDTCTIPGW            = $cidHash['MSDTCTIPGW']
                    DTCCID_MSDTCXATM             = $cidHash['MSDTCXATM']
                    networkDTCAccess             = $reg.networkDTCAccess
                    networkDTCAccessAdmin        = $reg.networkDTCAccessAdmin
                    networkDTCAccessClients      = $reg.networkDTCAccessClients
                    networkDTCAccessInbound      = $reg.networkDTCAccessInbound
                    networkDTCAccessOutBound     = $reg.networkDTCAccessOutBound
                    networkDTCAccessTip          = $reg.networkDTCAccessTip
                    networkDTCAccessTransactions = $reg.networkDTCAccessTransactions
                    XATransactions               = $reg.XATransactions
                }
            }
        }
    }
}