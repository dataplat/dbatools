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
                        Get-FilestreamReturnValue -Value $return.ReturnValue
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