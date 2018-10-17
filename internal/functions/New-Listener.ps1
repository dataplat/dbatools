function New-Listener {
    [CmdletBinding()]
    param (
        [object]$ag,
        [string]$Name,
        [int]$Port,
        [ipaddress]$IPAddress,
        [ipaddress]$SubnetMask,
        [switch]$Passthru
    )
    process {
        $eap = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        $EnableException = $true
        $aglistener = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener -ArgumentList $ag, $Name
        $aglistener.PortNumber = $Port
        $listenerip = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroupListenerIPAddress -ArgumentList $aglistener
        
        if (Test-Bound -ParameterName IPAddress) {
            $listenerip.IPAddress = $IPAddress.IPAddressToString
            $listenerip.SubnetMask = $SubnetMask.IPAddressToString
        }
        
        $listenerip.IsDHCP = $Dhcp
        $aglistener.AvailabilityGroupListenerIPAddresses.Add($listenerip)
        
        if ($Passthru) {
            return $aglistener
        }
        else {
            Write-Message -Level Verbose -Message "Performing create"
            $aglistener.Create()
        }
    }
}