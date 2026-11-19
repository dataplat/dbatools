#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- read-only network configuration; no ShouldProcess in the pin.
# NativeChecklist: sql-login N/A -- Windows Credential only; no SqlCredential or SQL connection.
# NativeChecklist: azure-sqldb N/A -- SQL Server WMI network configuration and host certificate stores are unavailable in Azure SQL Database: https://learn.microsoft.com/sql/relational-databases/wmi-provider-configuration/wmi-provider-for-configuration-management

Describe 'Native Get-DbaNetworkConfiguration real configuration' -Tag IntegrationTests {
    BeforeAll {
        $instance = [DbaInstanceParameter]$TestConfig.InstanceSingle
        $computer = $instance.ComputerName
        $snapshot = Invoke-Command -ComputerName $computer -ErrorAction Stop -ScriptBlock {
            param($instanceName)
            $null = [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
            $managed = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
            $null = $managed.Initialize()
            $protocols = $managed.ServerInstances[$instanceName].ServerProtocols
            $tcp = $protocols['Tcp']
            $addresses = @($tcp.IPAddresses | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Active = $_.IPAddressProperties['Active'].Value; Enabled = $_.IPAddressProperties['Enabled'].Value; IpAddress = $_.IPAddressProperties['IpAddress'].Value; TcpDynamicPorts = $_.IPAddressProperties['TcpDynamicPorts'].Value; TcpPort = $_.IPAddressProperties['TcpPort'].Value }
            })
            [pscustomobject]@{
                SharedMemoryEnabled = $protocols['Sm'].IsEnabled
                NamedPipesEnabled = $protocols['Np'].IsEnabled
                TcpIpEnabled = $tcp.IsEnabled
                Enabled = $tcp.ProtocolProperties['Enabled'].Value
                KeepAlive = $tcp.ProtocolProperties['KeepAlive'].Value
                ListenAll = $tcp.ProtocolProperties['ListenOnAllIPs'].Value
                Addresses = $addresses
            }
        } -ArgumentList $instance.InstanceName
    }
    It 'returns real protocol and IP configuration for each output form without changing it' {
        $full = @(Get-DbaNetworkConfiguration -SqlInstance $instance -EnableException)
        $full.Count | Should -Be 1
        $protocols = @(Get-DbaNetworkConfiguration -SqlInstance $instance -OutputType ServerProtocols -EnableException)
        $protocols.Count | Should -Be 1
        foreach ($name in 'SharedMemoryEnabled', 'NamedPipesEnabled', 'TcpIpEnabled') {
            $full[0].$name | Should -Be $snapshot.$name
            $protocols[0].$name | Should -Be $snapshot.$name
        }
        $tcp = Get-DbaNetworkConfiguration -SqlInstance $instance -OutputType TcpIpProperties -EnableException
        foreach ($name in 'Enabled', 'KeepAlive', 'ListenAll') {
            $tcp.$name | Should -Be $snapshot.$name
            $full[0].TcpIpProperties.$name | Should -Be $snapshot.$name
        }
        $addresses = @(Get-DbaNetworkConfiguration -SqlInstance $instance -OutputType TcpIpAddresses -EnableException)
        $expected = @($snapshot.Addresses | Where-Object { if ($snapshot.ListenAll) { $_.Name -eq 'IPAll' } else { $_.Name -ne 'IPAll' } })
        $addresses.Count | Should -Be $expected.Count
        foreach ($address in $addresses) {
            $match = $expected | Where-Object Name -eq $address.Name
            $address.TcpPort | Should -Be $match.TcpPort
            $address.TcpDynamicPorts | Should -Be $match.TcpDynamicPorts
            if (-not $snapshot.ListenAll) {
                foreach ($name in 'Active', 'Enabled', 'IpAddress') { $address.$name | Should -Be $match.$name }
            }
        }
        $certificate = Get-DbaNetworkConfiguration -SqlInstance $instance -OutputType certificate -EnableException
        $certificate.SqlInstance | Should -BeExactly $full[0].SqlInstance
        foreach ($name in 'VSName', 'ServiceAccount', 'ForceEncryption', 'FriendlyName', 'Thumbprint', 'Generated', 'Expires', 'IssuedTo', 'IssuedBy') {
            $certificate.$name | Should -Be $full[0].Certificate.$name
        }
    }
    It 'supports arrays and pipeline records with EnableException false' -Tag NativeChecklist:pipeline-multiple, NativeChecklist:switch-false {
        $rows = @($instance, $instance | Get-DbaNetworkConfiguration -OutputType ServerProtocols -EnableException:$false)
        $rows.Count | Should -Be 2
        $rows[0].SqlInstance | Should -BeExactly $rows[1].SqlInstance
        @(Get-DbaNetworkConfiguration -SqlInstance $instance, $instance -OutputType TcpIpProperties -EnableException:$false).Count | Should -Be 2
    }
    It 'continues past an absent instance and rejects invalid Windows credentials' -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $absent = $computer + '\ndba_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $rows = @(Get-DbaNetworkConfiguration -SqlInstance $absent, $instance -OutputType ServerProtocols -WarningVariable warnings -WarningAction SilentlyContinue)
        $rows.Count | Should -Be 1
        "$warnings" | Should -BeLike '*No data was found for this instance*'
        { Get-DbaNetworkConfiguration -SqlInstance $absent, $instance -EnableException } | Should -Throw -ErrorId 'dbatools_Get-DbaNetworkConfiguration*'
        $bad = New-Object System.Management.Automation.PSCredential -ArgumentList ($computer + '\native_' + [guid]::NewGuid().ToString('N')), (ConvertTo-SecureString 'Unused!native_9472' -AsPlainText -Force)
        @(Get-DbaNetworkConfiguration -SqlInstance $instance -Credential $bad -WarningAction SilentlyContinue).Count | Should -Be 0
        { Get-DbaNetworkConfiguration -SqlInstance $instance -Credential $bad -EnableException } | Should -Throw -ErrorId 'dbatools_Get-DbaNetworkConfiguration*'
    }
}

Describe 'Native Get-DbaNetworkConfiguration private key suitability' -Tag IntegrationTests {
    BeforeAll {
        $instance = [DbaInstanceParameter]$TestConfig.InstanceSingle
        $computer = $instance.ComputerName
        $owner = 'native_netconf_' + [guid]::NewGuid().ToString('N')
        $fixtures = Invoke-Command -ComputerName $computer -ErrorAction Stop -ScriptBlock {
            param($instanceName, $owner)
            $null = [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
            $managed = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
            $null = $managed.Initialize()
            $service = $managed.Services | Where-Object DisplayName -eq "SQL Server ($instanceName)"
            $virtual = ($service.AdvancedProperties | Where-Object Name -eq VSNAME).Value
            $networkName = if ($virtual) { $virtual } else { hostname }
            foreach ($kind in 'Decrypt', 'SignOnly', 'PublicOnly', 'InvalidPunycode') {
                $options = @{
                    DnsName = @($networkName, "$networkName.$env:USERDNSDOMAIN")
                    CertStoreLocation = 'Cert:\LocalMachine\My'
                    FriendlyName = $owner + '_' + $kind
                    KeyAlgorithm = 'RSA'
                    KeyLength = 2048
                    HashAlgorithm = 'SHA256'
                    KeyUsage = @('DigitalSignature', 'KeyEncipherment')
                    KeyUsageProperty = $(if ($kind -eq 'SignOnly') { 'Sign' } else { 'All' })
                    TextExtension = @('2.5.29.37={text}1.3.6.1.5.5.7.3.1')
                    Provider = 'Microsoft Software Key Storage Provider'
                    NotBefore = (Get-Date).AddMinutes(-5)
                }
                if ($kind -eq 'InvalidPunycode') { $options.DnsName += 'xn--' }
                $certificate = New-SelfSignedCertificate @options
                $thumbprint = $certificate.Thumbprint
                if ($kind -eq 'PublicOnly') {
                    $raw = $certificate.RawData
                    Remove-Item -LiteralPath ('Cert:\LocalMachine\My\' + $thumbprint) -DeleteKey -Force
                    $copy = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @(,$raw)
                    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList 'My', 'LocalMachine'
                    try {
                        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
                        $copy.FriendlyName = $owner + '_' + $kind
                        $store.Add($copy)
                    } finally { $store.Close(); $copy.Dispose() }
                }
                # Read a fresh store snapshot after replacing PublicOnly through a separate X509Store.
                $fixtureStore = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList "My", "LocalMachine"
                $fixtureCertificates = @()
                $rsa = $null
                try {
                    $fixtureStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
                    $fixtureCertificates = @($fixtureStore.Certificates)
                    $actual = @($fixtureCertificates | Where-Object Thumbprint -eq $thumbprint)
                    if ($actual.Count -ne 1) { throw "Expected one $kind fixture certificate $thumbprint, found $($actual.Count)." }
                    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($actual[0])
                    [pscustomobject]@{ Kind = $kind; Thumbprint = $thumbprint; HasPrivateKey = $actual[0].HasPrivateKey; AllowsDecryption = $null -ne $rsa -and ($rsa.Key.KeyUsage -band [System.Security.Cryptography.CngKeyUsages]::Decryption) -ne 0; NetworkName = $networkName; DnsNames = @($actual[0].DnsNameList.Unicode) }
                } finally {
                    if ($rsa) { $rsa.Dispose() }
                    foreach ($fixtureCertificate in $fixtureCertificates) { $fixtureCertificate.Dispose() }
                    $fixtureStore.Dispose()
                }
            }
        } -ArgumentList $instance.InstanceName, $owner
    }
    AfterAll {
        if ($computer -and $owner) {
            $remaining = Invoke-Command -ComputerName $computer -ErrorAction Stop -ScriptBlock {
                param($owner)
                foreach ($certificate in Get-ChildItem Cert:\LocalMachine -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -like ($owner + '_*') }) {
                    if ($certificate.HasPrivateKey) { Remove-Item -LiteralPath $certificate.PSPath -DeleteKey -Force -ErrorAction Stop }
                    else { Remove-Item -LiteralPath $certificate.PSPath -Force -ErrorAction Stop }
                }
                @(Get-ChildItem Cert:\LocalMachine -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -like ($owner + '_*') }).Count
            } -ArgumentList $owner
            $remaining | Should -Be 0
        }
    }
    It 'requires a real decryption-capable private key instead of assuming every certificate is suitable' {
        $fixtures.Count | Should -Be 4
        ($fixtures | Where-Object Kind -eq Decrypt).AllowsDecryption | Should -BeTrue
        ($fixtures | Where-Object Kind -eq SignOnly).AllowsDecryption | Should -BeFalse
        ($fixtures | Where-Object Kind -eq PublicOnly).HasPrivateKey | Should -BeFalse
        $rows = Get-DbaNetworkConfiguration -SqlInstance $instance -EnableException
        $rows.SuitableCertificate.Thumbprint | Should -Contain ($fixtures | Where-Object Kind -eq Decrypt).Thumbprint
        foreach ($fixture in $fixtures | Where-Object Kind -in @('SignOnly', 'PublicOnly')) { $rows.SuitableCertificate.Thumbprint | Should -Not -Contain $fixture.Thumbprint }
    }
    It 'retains a matching certificate when another SAN is not valid Punycode' {
        $fixture = $fixtures | Where-Object Kind -eq InvalidPunycode
        $fixture.AllowsDecryption | Should -BeTrue
        $fixture.DnsNames | Should -Contain $fixture.NetworkName
        $fixture.DnsNames | Should -Contain 'xn--'
        { (New-Object System.Globalization.IdnMapping).GetUnicode('xn--') } | Should -Throw
        $rows = Get-DbaNetworkConfiguration -SqlInstance $instance -EnableException
        $rows.SuitableCertificate.Thumbprint | Should -Contain $fixture.Thumbprint
    }
}
