#ValidationTags#Messaging#
function Get-DbaMsdtc {
    <#
        .SYNOPSIS
            Displays information about the Distributed Transaction Coordinator (MSDTC) on a server

        .DESCRIPTION
            Returns a custom object with Computer name, state of the MSDTC Service, security settings of MSDTC and CID's

            Requires: Windows administrator access on Servers

        .PARAMETER ComputerName
            The SQL Server (or server in general) that you're connecting to.

        .NOTES
            Tags: Msdtc, dtc
            Author: Klaas Vandenberghe ( powerdbaklaas )

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaMsdtc

        .EXAMPLE
            Get-DbaMsdtc -ComputerName srv0042

            Get DTC status for the server srv0042

        .EXAMPLE
            $Computers = (Get-Content D:\configfiles\SQL\MySQLInstances.txt | % {$_.split('\')[0]})
            $Computers | Get-DbaMsdtc

            Get DTC status for all the computers in a .txt file

        .EXAMPLE
            Get-DbaMsdtc -Computername $Computers | where { $_.dtcservicestate -ne 'running' }

            Get DTC status for all the computers where the MSDTC Service is not running

        .EXAMPLE
            Get-DbaMsdtc -ComputerName srv0042 | Out-Gridview

            Get DTC status for the computer srv0042 and show in a grid view
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [Alias('cn', 'host', 'Server')]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME
    )

    begin {
        $ComputerName = $ComputerName | ForEach-Object {$_.split("\")[0]} | Select-Object -Unique
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
        foreach ($computer in $ComputerName) {
            $reg = $cids = $null
            $cidHash = @{}
            if ( Test-PSRemoting -ComputerName $computer ) {
                $dtcservice = $null
                Write-Message -Level Verbose -Message "Getting DTC on $computer via WSMan"
                $dtcservice = Get-Ciminstance -ComputerName $computer -Query $query
                if ( $null -eq $dtcservice ) {
                    Write-Warning "Can't connect to CIM on $computer via WSMan"
                }

                Write-Message -Level Verbose -Message "Getting MSDTC Security Registry Values on $computer"
                $reg = Invoke-Command -ComputerName $computer -ScriptBlock $dtcSecurity
                if ( $null -eq $reg ) {
                    Write-Message -Level Warning -Message "Can't connect to MSDTC Security registry on $computer"
                }
                Write-Message -Level Verbose -Message "Getting MSDTC CID Registry Values on $computer"
                $cids = Invoke-Command -ComputerName $computer -ScriptBlock $dtcCids
                if ( $null -ne $cids ) {
                    foreach ($key in $cids) {
                        $cidHash.Add($key.Data, $key.CID)
                    }
                }
                else {
                    Write-Message -Level Warning -Message "Can't connect to MSDTC CID registry on $computer"
                }
            }
            else {
                Write-Message -Level Verbose -Message "PSRemoting is not enabled on $computer"
                try {
                    Write-Message -Level Verbose -Message "Failed To get DTC via WinRM. Getting DTC on $computer via DCom"
                    $SessionParams = @{ }
                    $SessionParams.ComputerName = $Computer
                    $SessionParams.SessionOption = (New-CimSessionOption -Protocol Dcom)
                    $Session = New-CimSession @SessionParams
                    $dtcservice = Get-Ciminstance -CimSession $Session -Query $query
                }
                catch {
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
