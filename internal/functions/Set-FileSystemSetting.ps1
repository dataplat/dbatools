function Set-FileSystemSetting {
    # not available in SQL WMI
    [CmdletBinding()]
    param (
        [DbaInstance]$Instance,
        [PSCredential]$Credential,
        [string]$ShareName,
        [int]$FilestreamLevel
    )
    begin {
        function Get-WmiFilestreamReturnValue {
            [CmdletBinding()]
            param (
                [object]$Value
            )
            switch ($Value) {
                2147217396 {
                    "Filestream not supported on instance"
                }
                2147217386 {
                    "Filestream cannot change share"
                }
                2147024713 {
                    "Duplicate sharename"
                }
                2147024891 {
                    "Access denied"
                }
                2147023681 {
                    "Invalid sharename"
                }
                2147024690 {
                    "Sharename too long"
                }
                2147019889 {
                    "Primary node not enabled "
                }
                2147019848 {
                    "Sharename node mismatch"
                }
                214721740 {
                    "General error"
                }
                { 2147021885 -or 2147945411 -or 0 } {
                    "The requested operation is successful. Changes will not be effective until the service is restarted."
                }
                default {
                    $return.ReturnValue
                }
            }
        }

        function Get-WmiFilestreamSetting {
            # not available in SQL WMI
            [CmdletBinding()]
            param (
                [DbaInstance]$Instance,
                [PSCredential]$Credential
            )

            $computer = $computerName = $Machine = $instance.ComputerName
            $instanceName = $instance.InstanceName

            Write-Message -Level Verbose -Message "Attempting to connect to $computer's WMI"
            $ognamespace = Get-DbaCmObject -EnableException -ComputerName $computerName -Namespace root\Microsoft\SQLServer -Query "SELECT NAME FROM __NAMESPACE WHERE NAME LIKE 'ComputerManagement%'"
            $namespace = $ognamespace | Where-Object {
                (Get-DbaCmObject -EnableException -ComputerName $computerName -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -ClassName FilestreamSettings).Count -gt 0
            } |
            Sort-Object Name -Descending | Select-Object -First 1

        if (-not $namespace) {
            $namespace = $ognamespace
        }

        if ($namespace.Name) {
            if ($Credential) {
                $wmi = Get-WmiObject -Credential $Credential -ErrorAction Stop -ComputerName $computerName -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -Class FilestreamSettings | Where-Object InstanceName -eq $instanceName | Select-Object -First 1
            } else {
                $wmi = Get-WmiObject -ErrorAction Stop -ComputerName $computerName -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -Class FilestreamSettings | Where-Object InstanceName -eq $instanceName | Select-Object -First 1
            }
        }
        $wmi
    }
}
process {
    # Server level
    if ($Force -or $PSCmdlet.ShouldProcess($instance, "Enabling filestream")) {
        try {
            $wmi = Get-WmiFilestreamSetting -Instance $instance -ErrorAction Stop
            if ($ShareName) {
                $null = $wmi.ShareName = $ShareName
            }
            $return = $wmi.EnableFilestream($FileStreamLevel, $instance.InstanceName)
            $returnvalue = Get-WmiFilestreamReturnValue -Value $return.ReturnValue
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
        }
    }
    $returnvalue
}
}