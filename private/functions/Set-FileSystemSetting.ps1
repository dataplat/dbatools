function Set-FileSystemSetting {
    # not available in SQL WMI
    [CmdletBinding()]
    param (
        [DbaInstance]$Instance,
        [PSCredential]$Credential,
        [string]$ShareName,
        [int]$FilestreamLevel,
        [switch]$EnableException
    )
    begin {
        function Get-FilestreamReturnValue {
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
                    $Value
                }
            }
        }
    }

    process {
        if ($Force -or $PSCmdlet.ShouldProcess($Instance, "Setting filestream")) {
            try {
                $computerName = $Instance.ComputerName
                $instanceName = $Instance.InstanceName

                Write-Message -Level Verbose -Message "Attempting to connect to $computerName's CIM"
                $namespaces = Get-DbaCmObject -ComputerName $computerName -Credential $Credential -Namespace root\Microsoft\SQLServer -Query "SELECT NAME FROM __NAMESPACE WHERE NAME LIKE 'ComputerManagement%'" -EnableException
                $fileStreamNamespace = $namespaces | Where-Object { (@(Get-DbaCmObject -ComputerName $computerName -Credential $Credential -Namespace "root\Microsoft\SQLServer\$($PSItem.Name)" -ClassName FilestreamSettings -EnableException)).Count -gt 0 } | Sort-Object Name -Descending | Select-Object -First 1
                if ($fileStreamNamespace) {
                    $fileStreamCim = Get-DbaCmObject -ComputerName $computerName -Credential $Credential -Namespace root\Microsoft\SQLServer\$($fileStreamNamespace.Name) -ClassName FilestreamSettings | Where-Object { $PSItem.InstanceName -eq $instanceName }
                    if ($fileStreamCim) {
                        if (-not $ShareName) {
                            $ShareName = $instance.InstanceName
                        }
                        $arguments = @{
                            AccessLevel = $FileStreamLevel
                            ShareName   = $ShareName
                        }
                        $return = Invoke-CimMethod -InputObject $fileStreamCim -MethodName EnableFilestream -Arguments $arguments
                        $returnvalue = Get-FilestreamReturnValue -Value $return.ReturnValue
                        $returnvalue
                    } else {
                        Stop-Function -Message "No cim object for class FilestreamSettings found"
                    }
                } else {
                    Stop-Function -Message "No cim namespace with class FilestreamSettings found"
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}