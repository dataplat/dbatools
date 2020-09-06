function Test-PendingReboot {
    <#
        .SYNOPSIS
            Based on https://github.com/adbertram/PSSqlUpdater
            This function tests various registry values to see if the local computer is pending a reboot
        .NOTES
            Inspiration from: https://gallery.technet.microsoft.com/scriptcenter/Get-PendingReboot-Query-bdb79542
        .EXAMPLE
            PS> Test-PendingReboot

            This example checks various registry values to see if the local computer is pending a reboot.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [DbaInstanceParameter]$ComputerName,
        [pscredential]$Credential,
        [switch]$PendingRename
    )
    process {
        $icmParams = @{
            ComputerName = $ComputerName.ComputerName
            Raw          = $true
            ErrorAction  = 'Stop'
        }
        if (Test-Bound -ParameterName Credential) {
            $icmParams.Credential = $Credential
        }

        $OperatingSystem = Get-DbaCmObject -ComputerName $ComputerName.ComputerName  -Credential $Credential -ClassName Win32_OperatingSystem -EnableException

        # If Vista/2008 & Above query the CBS Reg Key
        If ($OperatingSystem.BuildNumber -ge 6001) {
            $PendingReboot = Invoke-Command2 @icmParams -ScriptBlock { Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing' -Name 'RebootPending' -ErrorAction SilentlyContinue }
            if ($PendingReboot) {
                Write-Message -Level Verbose -Message 'Reboot pending detected in the Component Based Servicing registry key'
                return $true
            }
        }

        # Query WUAU from the registry
        $PendingReboot = Invoke-Command2 @icmParams -ScriptBlock { Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' -Name 'RebootRequired' -ErrorAction SilentlyContinue }
        if ($PendingReboot) {
            Write-Message -Level Verbose -Message 'WUAU has a reboot pending'
            return $true
        }

        # Query PendingFileRenameOperations from the registry
        if ($PendingRename) {
            $PendingReboot = Invoke-Command2 @icmParams -ScriptBlock { Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue }
            if ($PendingReboot -and $PendingReboot.PendingFileRenameOperations) {
                Write-Message -Level Verbose -Message 'Reboot pending in the PendingFileRenameOperations registry value'
                return $true
            }
        }
        return $false
    }
}
