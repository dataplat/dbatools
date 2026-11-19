#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = 'dbatools',
    $CommandName = 'Set-DbaCmConnection',
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: azure-sqldb N/A -- This command configures process-local management connection records. It has no database target.

Describe 'Set-DbaCmConnection native' -Tag IntegrationTests {
    BeforeEach {
        $cache = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections
        $name = 'ncma' + [guid]::NewGuid().ToString('N').Substring(0, 9)
        $other = 'ncmb' + [guid]::NewGuid().ToString('N').Substring(0, 9)
        $first = New-Object Dataplat.Dbatools.Connection.ManagementConnection -ArgumentList $name
        $second = New-Object Dataplat.Dbatools.Connection.ManagementConnection -ArgumentList $other
        $cache[$name] = $first
        $cache[$other] = $second
        $localWasCached = $cache.ContainsKey($env:COMPUTERNAME.ToLowerInvariant())
    }

    AfterEach {
        $null = $cache.Remove($name)
        $null = $cache.Remove($other)
        if (-not $localWasCached) {
            $null = $cache.Remove($env:COMPUTERNAME.ToLowerInvariant())
        }
    }

    It 'disables credential failover without changing automatic registration' {
        $first.EnableCredentialFailover = $true
        $first.DisableCredentialAutoRegister = $true
        $result = Set-DbaCmConnection -ComputerName $name -EnableCredentialFailover:$false -Confirm:$false
        $result.EnableCredentialFailover | Should -BeFalse
        $result.DisableCredentialAutoRegister | Should -BeTrue
    }

    It 'applies bound false switches while leaving unbound switches alone' -Tag NativeChecklist:switch-false {
        $first.DisableCimPersistence = $true
        $first.OverrideConnectionPolicy = $true
        $result = Set-DbaCmConnection -ComputerName $name -DisableCimPersistence:$false -Confirm:$false
        $result.DisableCimPersistence | Should -BeFalse
        $result.OverrideConnectionPolicy | Should -BeTrue
    }

    It 'emits the original cached records in pipeline order' -Tag NativeChecklist:pipeline-multiple {
        $records = @($other, $name | Set-DbaCmConnection -DisableCimPersistence -Confirm:$false)
        $records.Count | Should -Be 2
        [object]::ReferenceEquals($records[0], $second) | Should -BeTrue
        [object]::ReferenceEquals($records[1], $first) | Should -BeTrue
        $records.DisableCimPersistence | Should -Be @($true, $true)
    }

    It 'reapplies the default only when the computer is supplied by the pipeline' {
        $originalName = $env:COMPUTERNAME
        $localName = 'ncl' + [guid]::NewGuid().ToString('N').Substring(0, 9)
        try {
            $env:COMPUTERNAME = $localName
            $null = Set-DbaCmConnection -ComputerName $name -DisableCimPersistence -Confirm:$false
            $cache.ContainsKey($localName) | Should -BeFalse
            $records = @(& {
                $name
                $null = $cache.Remove($localName)
                $other
            } | Set-DbaCmConnection -DisableCimPersistence -Confirm:$false)
            $records.ComputerName | Should -Be @($name, $other)
            $cache.ContainsKey($localName) | Should -BeTrue
        } finally {
            $env:COMPUTERNAME = $originalName
            $null = $cache.Remove($localName)
        }
    }

    It 'restores a previously exported connection record through the documented pipeline' {
        $first.LastWmi = [datetime]'2020-01-01T00:00:00Z'
        $first.Wmi = 'Success'
        $first.DisableCimPersistence = $true
        $fixture = Join-Path $TestDrive "$name.xml"
        $first | Export-Clixml -LiteralPath $fixture
        $null = $cache.Remove($name)
        $result = @(Import-Clixml -LiteralPath $fixture | Set-DbaCmConnection -ResetConfiguration -EnableException -Confirm:$false)
        $result.Count | Should -Be 1
        $result[0].ComputerName | Should -Be $name
        $result[0].LastWmi | Should -Be $first.LastWmi
        $cache[$name].LastWmi | Should -Be $first.LastWmi
    }

    It 'retains a timeout on an exported credential-free record that already has CIM options' {
        $options = New-CimSessionOption -Protocol Wsman
        $options.Timeout = [timespan]::FromSeconds(38)
        $record = Set-DbaCmConnection -ComputerName $name -CimWinRMOptions $options -Confirm:$false
        $fixture = Join-Path $TestDrive "$name.xml"
        $record | Export-Clixml -LiteralPath $fixture
        $null = $cache.Remove($name)
        $restored = Import-Clixml -LiteralPath $fixture | Set-DbaCmConnection -Confirm:$false -EnableException
        $restored.ComputerName | Should -Be $name
        $restored.CimWinRMOptions.Timeout | Should -Be $options.Timeout
        $restored.CimDComOptions.PacketPrivacy | Should -Be $record.CimDComOptions.PacketPrivacy
    }

    It 'declines a credential-bearing import before writing the record to the cache' {
        $secret = New-Object System.Security.SecureString
        try {
            $first.Credentials = New-Object System.Management.Automation.PSCredential -ArgumentList 'local-fixture', $secret
            $fixture = Join-Path $TestDrive "$name.xml"
            $first | Export-Clixml -LiteralPath $fixture
            $null = $cache.Remove($name)
            { Import-Clixml -LiteralPath $fixture | Set-DbaCmConnection -Confirm:$false -EnableException } | Should -Throw '*Failed to interpret computername input*'
            $cache.ContainsKey($name) | Should -BeFalse
        } finally { $secret.Dispose() }
    }

    It 'declines an imported connection policy override before writing the record to the cache' {
        $first.OverrideConnectionPolicy = $true
        $fixture = Join-Path $TestDrive "$name.xml"
        $first | Export-Clixml -LiteralPath $fixture
        $null = $cache.Remove($name)
        { Import-Clixml -LiteralPath $fixture | Set-DbaCmConnection -Confirm:$false -EnableException } | Should -Throw '*Failed to interpret computername input*'
        $cache.ContainsKey($name) | Should -BeFalse
    }

    It 'updates exported history without replacing the live record or its disabled protocol' {
        $snapshot = New-Object Dataplat.Dbatools.Connection.ManagementConnection -ArgumentList $name
        $snapshot.LastWmi = [datetime]'2020-02-02T00:00:00Z'
        $snapshot.Wmi = 'Success'
        $fixture = Join-Path $TestDrive "$name.xml"
        $snapshot | Export-Clixml -LiteralPath $fixture
        $first.Wmi = 'Disabled'
        $updated = Import-Clixml -LiteralPath $fixture | Set-DbaCmConnection -EnableException -Confirm:$false
        [object]::ReferenceEquals($updated, $first) | Should -BeTrue
        $updated.LastWmi | Should -Be $snapshot.LastWmi
        $updated.Wmi | Should -Be 'Disabled'
    }

    It 'warns about an invalid input and still updates the next record' -Tag NativeChecklist:multi-instance-failure {
        $warnings = @()
        $result = @(Set-DbaCmConnection -ComputerName 'not a target', $name -DisableCimPersistence -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -Confirm:$false)
        $result.Count | Should -Be 1
        $result[0].ComputerName | Should -Be $name
        $result[0].DisableCimPersistence | Should -BeTrue
        ($warnings -join ' ') | Should -Match 'Failed to interpret computername input: not a target'
    }

    It 'raises an invalid argument and preserves the following record under EnableException' -Tag NativeChecklist:enable-exception {
        $second.DisableCimPersistence = $false
        $caught = $null
        try {
            $null = Set-DbaCmConnection -ComputerName 'not a target', $other -DisableCimPersistence -EnableException -Confirm:$false
        } catch { $caught = $_ }
        $caught | Should -Not -BeNullOrEmpty
        $caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $caught.TargetObject | Should -Be 'not a target'
        $second.DisableCimPersistence | Should -BeFalse
    }

    It 'leaves the existing record unchanged under WhatIf and applies a confirmed edit' -Tag NativeChecklist:whatif-confirm {
        $first.DisableCimPersistence = $false
        @(Set-DbaCmConnection -ComputerName $name -DisableCimPersistence -WhatIf -Confirm:$false).Count | Should -Be 0
        $first.DisableCimPersistence | Should -BeFalse
        $updated = Set-DbaCmConnection -ComputerName $name -DisableCimPersistence -Confirm:$false
        $updated.DisableCimPersistence | Should -BeTrue
    }

    It 'clears stored status and applies the requested settings after restoring defaults' {
        $first.Wmi = 'Error'
        $first.CimRM = 'Error'
        $first.LastWmi = [datetime]::UtcNow
        $first.LastCimRM = [datetime]::UtcNow
        $first.WindowsCredentialsAreBad = $true
        $result = Set-DbaCmConnection -ComputerName $name -ResetConfiguration -ResetConnectionStatus -ResetCredential -DisableCimPersistence -OverrideConnectionPolicy -Confirm:$false
        $result.Wmi | Should -Be 'Unknown'
        $result.CimRM | Should -Be 'Unknown'
        $result.LastWmi | Should -Be ([datetime]::MinValue)
        $result.LastCimRM | Should -Be ([datetime]::MinValue)
        $result.WindowsCredentialsAreBad | Should -BeFalse
        $result.DisableCimPersistence | Should -BeTrue
    }

    It 'keeps custom WinRM options and clears them when explicitly passed null' {
        $options = New-CimSessionOption -Protocol Wsman
        $options.Timeout = [timespan]::FromSeconds(37)
        $result = Set-DbaCmConnection -ComputerName $name -CimWinRMOptions $options -Confirm:$false
        $result.CimWinRMOptions.Timeout | Should -Be $options.Timeout
        $result = Set-DbaCmConnection -ComputerName $name -ClearCredential -Confirm:$false
        $result.CimWinRMOptions.Timeout | Should -Be $options.Timeout
        $result = Set-DbaCmConnection -ComputerName $name -CimWinRMOptions $null -Confirm:$false
        $result.CimWinRMOptions | Should -BeNullOrEmpty
    }

    It 'preserves the configured timeout when reading back DCOM options' {
        $options = New-CimSessionOption -Protocol Dcom
        $options.Timeout = [timespan]::FromSeconds(41)
        $result = Set-DbaCmConnection -ComputerName $name -CimDCOMOptions $options -Confirm:$false
        $result.CimDComOptions.Timeout | Should -Be $options.Timeout
        $result.CimDComOptions.PacketPrivacy | Should -Be $options.PacketPrivacy
        $result.CimDComOptions.PacketIntegrity | Should -Be $options.PacketIntegrity
        $result.CimDComOptions.Impersonation | Should -Be $options.Impersonation
    }

    It 'removes a known bad credential without throwing or removing another' {
        $secret = New-Object System.Security.SecureString
        try {
            $remove = New-Object System.Management.Automation.PSCredential -ArgumentList 'local-fixture-one', $secret
            $keep = New-Object System.Management.Automation.PSCredential -ArgumentList 'local-fixture-two', $secret
            $first.DisableBadCredentialCache = $false
            $null = Set-DbaCmConnection -ComputerName $name -AddBadCredential $remove, $keep -Confirm:$false
            $first.KnownBadCredentials.Count | Should -Be 2
            $caught = $null
            try {
                $result = Set-DbaCmConnection -ComputerName $name -RemoveBadCredential $remove -Confirm:$false -ErrorAction Stop
            } catch { $caught = $_ }
            $caught | Should -BeNullOrEmpty
            $result.KnownBadCredentials.Count | Should -Be 1
            [object]::ReferenceEquals($result.KnownBadCredentials[0], $keep) | Should -BeTrue
        } finally {
            $secret.Dispose()
        }
    }
}
