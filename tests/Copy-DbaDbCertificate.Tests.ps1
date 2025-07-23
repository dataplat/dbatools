#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Copy-DbaDbCertificate" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaDbCertificate
            $expected = $TestConfig.CommonParameters
            $expected += @(
                'Source',
                'SourceSqlCredential',
                'Destination',
                'DestinationSqlCredential',
                'Database',
                'ExcludeDatabase',
                'Certificate',
                'ExcludeCertificate',
                'SharedPath',
                'MasterKeyPassword',
                'EncryptionPassword',
                'DecryptionPassword',
                'EnableException',
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasParams = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasParams | Should -BeNullOrEmpty
        }
    }
}

Describe "Copy-DbaDbCertificate" -Tag "IntegrationTests" {
    Context "Can create a database certificate" {
        BeforeAll {
            $securePassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force

            # Create master key on instance2
            $masterKey = New-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database master -SecurePassword $securePassword -Confirm:$false -ErrorAction SilentlyContinue

            # Create test databases
            $testDatabases = New-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Name dbatoolscopycred

            # Create master key and certificate on source
            $null = New-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database dbatoolscopycred -SecurePassword $securePassword -Confirm:$false
            $certificateName = "Cert_$(Get-Random)"
            $null = New-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Name $certificateName -Database dbatoolscopycred -Confirm:$false

            # Setup copy parameters
            $splatCopyCert = @{
                Source             = $TestConfig.instance2
                Destination        = $TestConfig.instance3
                EncryptionPassword = $securePassword
                MasterKeyPassword  = $securePassword
                Database           = "dbatoolscopycred"
                SharedPath         = $TestConfig.appveyorlabrepo
                Confirm            = $false
            }
        }

        AfterAll {
            $null = $testDatabases | Remove-DbaDatabase -Confirm:$false -ErrorAction SilentlyContinue
            if ($masterKey) {
                $masterKey | Remove-DbaDbMasterKey -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        It -Skip "Successfully copies a certificate" {
            $results = Copy-DbaDbCertificate @splatCopyCert | Where-Object SourceDatabase -eq dbatoolscopycred | Select-Object -First 1

            $results.Notes | Should -BeNullOrEmpty
            $results.Status | Should -Be "Successful"

            $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database dbatoolscopycred
            $destDb = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database dbatoolscopycred

            $results.SourceDatabaseID | Should -Be $sourceDb.ID
            $results.DestinationDatabaseID | Should -Be $destDb.ID

            Get-DbaDbCertificate -SqlInstance $TestConfig.instance3 -Database dbatoolscopycred -Certificate $certificateName | Should -Not -BeNullOrEmpty
        }
    }
}
