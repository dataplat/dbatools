#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: sql-login N/A -- the pinned command has no SqlCredential and opens no SQL connection; Credential is a Windows credential.
# NativeChecklist: azure-sqldb N/A -- Azure SQL Database enforces encrypted connections and exposes no Windows SQL service registry to disable encryption. https://learn.microsoft.com/azure/azure-sql/database/security-overview
param(
    $ModuleName = "dbatools",
    $CommandName = "Disable-DbaForceNetworkEncryption",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Disable-DbaForceNetworkEncryption" -Tag IntegrationTests {
    BeforeAll {
        $nativeEncryptionInstance = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $TestConfig.InstanceSingle
        $nativeEncryptionComputer = $nativeEncryptionInstance.ComputerName
        $nativeEncryptionInstanceName = $nativeEncryptionInstance.InstanceName
        $nativeEncryptionSession = New-PSSession -ComputerName $nativeEncryptionComputer -ErrorAction Stop
        $nativeEncryptionState = Invoke-Command -Session $nativeEncryptionSession -ArgumentList $nativeEncryptionInstanceName -ErrorAction Stop -ScriptBlock {
            param($instanceName)
            $instanceMap = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' -ErrorAction Stop
            $instanceId = $instanceMap.$instanceName
            if (-not $instanceId) { throw 'Missing SQL instance registry mapping.' }
            $key = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer\SuperSocketNetLib"
            $values = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            $network = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
            $identity = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            [pscustomobject]@{ Key = $key; Value = $values.ForceEncryption; Certificate = $values.Certificate; ComputerName = $env:COMPUTERNAME; DnsSuffix = $network.DomainName; DnsHostName = $identity.DNSHostName; Domain = $identity.Domain }
        }
        $nativeEncryptionState.Value | Should -Not -BeNullOrEmpty
    }

    AfterAll {
        if ($nativeEncryptionSession) {
            try {
                if ($nativeEncryptionState) {
                    Invoke-Command -Session $nativeEncryptionSession -ArgumentList $nativeEncryptionState.Key, $nativeEncryptionState.Value -ErrorAction Stop -ScriptBlock {
                        param($key, $value)
                        Set-ItemProperty -LiteralPath $key -Name ForceEncryption -Value $value -ErrorAction Stop
                    }
                }
            } finally {
                Remove-PSSession -Session $nativeEncryptionSession
            }
        }
    }

    BeforeEach {
        Invoke-Command -Session $nativeEncryptionSession -ArgumentList $nativeEncryptionState.Key -ErrorAction Stop -ScriptBlock {
            param($key)
            Set-ItemProperty -LiteralPath $key -Name ForceEncryption -Value 1 -ErrorAction Stop
        }
    }

    AfterEach {
        Invoke-Command -Session $nativeEncryptionSession -ArgumentList $nativeEncryptionState.Key, $nativeEncryptionState.Value -ErrorAction Stop -ScriptBlock {
            param($key, $value)
            Set-ItemProperty -LiteralPath $key -Name ForceEncryption -Value $value -ErrorAction Stop
        }
    }

    It "resolves the target FQDN and primary DNS suffix from native management APIs" {
        $resolvedEncryptionHost = [Dataplat.Dbatools.Connection.NetworkResolutionService]::Resolve($null, $nativeEncryptionInstance, $null, $false)
        $resolvedEncryptionHost | Should -Not -BeNullOrEmpty
        $resolvedEncryptionHost.ComputerName | Should -Be $nativeEncryptionState.ComputerName
        $resolvedEncryptionHost.DNSHostname | Should -Be $nativeEncryptionState.DnsHostName
        $resolvedEncryptionHost.Domain | Should -Be $nativeEncryptionState.Domain
        $resolvedEncryptionHost.DNSDomain | Should -Be $nativeEncryptionState.DnsSuffix
        $expectedEncryptionFqdn = ($nativeEncryptionState.DnsHostName + '.' + $nativeEncryptionState.DnsSuffix).TrimEnd('.')
        $resolvedEncryptionHost.FullComputerName | Should -Be $expectedEncryptionFqdn
    }

    It "disables the registry value and returns the target identity and certificate" -Tag "NativeChecklist:switch-false" {
        $nativeEncryptionOutput = @(Disable-DbaForceNetworkEncryption -SqlInstance $TestConfig.InstanceSingle -WhatIf:$false -Confirm:$false -EnableException)
        $nativeEncryptionOutput.Count | Should -Be 1
        $nativeEncryptionOutput[0].PSObject.TypeNames[0] | Should -BeExactly 'Selected.System.Management.Automation.PSCustomObject'
        $nativeEncryptionOutput[0].ForceEncryption | Should -BeFalse
        $nativeEncryptionOutput[0].ComputerName | Should -BeExactly $nativeEncryptionState.ComputerName
        $nativeEncryptionOutput[0].InstanceName | Should -BeExactly $nativeEncryptionInstanceName
        $nativeEncryptionOutput[0].SqlInstance | Should -Not -BeNullOrEmpty
        $nativeEncryptionOutput[0].CertificateThumbprint | Should -Be $nativeEncryptionState.Certificate
        $readback = Invoke-Command -Session $nativeEncryptionSession -ArgumentList $nativeEncryptionState.Key -ErrorAction Stop -ScriptBlock {
            param($key)
            (Get-ItemProperty -LiteralPath $key -Name ForceEncryption -ErrorAction Stop).ForceEncryption
        }
        $readback | Should -Be 0
    }

    It "leaves the registry unchanged under WhatIf" -Tag "NativeChecklist:whatif-confirm" {
        @(Disable-DbaForceNetworkEncryption -SqlInstance $TestConfig.InstanceSingle -WhatIf -Confirm:$false -EnableException).Count | Should -Be 0
        $readback = Invoke-Command -Session $nativeEncryptionSession -ArgumentList $nativeEncryptionState.Key -ErrorAction Stop -ScriptBlock {
            param($key)
            (Get-ItemProperty -LiteralPath $key -Name ForceEncryption -ErrorAction Stop).ForceEncryption
        }
        $readback | Should -Be 1
    }

    It "continues around a missing middle service and preserves both output records" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $missingEncryptionInstance = $nativeEncryptionComputer + '\NM' + [guid]::NewGuid().ToString('N').Substring(0, 10)
        $nativeEncryptionWarnings = @()
        $nativeEncryptionOutput = @(@($TestConfig.InstanceSingle, $missingEncryptionInstance, $TestConfig.InstanceSingle) | Disable-DbaForceNetworkEncryption -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable nativeEncryptionWarnings)
        $nativeEncryptionOutput.Count | Should -Be 2
        $nativeEncryptionOutput[0].ForceEncryption | Should -BeFalse
        $nativeEncryptionOutput[1].ForceEncryption | Should -BeFalse
        ($nativeEncryptionWarnings -join ' ') | Should -BeLike "*Can't find instance*"
    }

    It "retains earlier output before EnableException terminates on a missing service" -Tag "NativeChecklist:enable-exception" {
        $missingEncryptionInstance = $nativeEncryptionComputer + '\NM' + [guid]::NewGuid().ToString('N').Substring(0, 10)
        $nativeEncryptionSeen = New-Object System.Collections.ArrayList
        $nativeEncryptionError = $null
        try {
            @($TestConfig.InstanceSingle, $missingEncryptionInstance, $TestConfig.InstanceSingle) | Disable-DbaForceNetworkEncryption -Confirm:$false -EnableException | ForEach-Object { $null = $nativeEncryptionSeen.Add($_) }
        } catch {
            $nativeEncryptionError = $_
        }
        $nativeEncryptionSeen.Count | Should -Be 1
        $nativeEncryptionError | Should -Not -BeNullOrEmpty
        $nativeEncryptionError.CategoryInfo.Category | Should -Be 'ObjectNotFound'
    }
}
