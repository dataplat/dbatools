function Get-WmiHadr {
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {

            try {
                $computer = $computerName = $instance.ComputerName
                $instanceName = $instance.InstanceName
                $currentState = Invoke-ManagedComputerCommand -ComputerName $computerName -ScriptBlock { $wmi.Services[$args[0]] | Select-Object IsHadrEnabled } -ArgumentList $instanceName -Credential $Credential
            } catch {
                Stop-Function -Message "Failure connecting to $computer" -Category ConnectionError -ErrorRecord $_ -Target $instance
                return
            }

            if ($null -eq $currentState.IsHadrEnabled) {
                $isEnabled = $false
            } else {
                $isEnabled = $currentState.IsHadrEnabled
            }
            [PSCustomObject]@{
                ComputerName  = $computer
                InstanceName  = $instanceName
                SqlInstance   = $instance.FullName
                IsHadrEnabled = $isEnabled
            }
        }
    }
}