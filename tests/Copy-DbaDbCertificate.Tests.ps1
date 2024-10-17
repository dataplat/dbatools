param($ModuleName = 'dbatools')

Describe "Copy-DbaDbCertificate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaDbCertificate
        }
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type DbaInstanceParameter
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type PSCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type String[]
        }
        It "Should have Certificate as a parameter" {
            $CommandUnderTest | Should -HaveParameter Certificate -Type String[]
        }
        It "Should have ExcludeCertificate as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeCertificate -Type String[]
        }
        It "Should have SharedPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter SharedPath -Type String
        }
        It "Should have MasterKeyPassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter MasterKeyPassword -Type SecureString
        }
        It "Should have EncryptionPassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter EncryptionPassword -Type SecureString
        }
        It "Should have DecryptionPassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter DecryptionPassword -Type SecureString
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Copy-DbaDbCertificate Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Can create a database certificate" {
        BeforeAll {
            $passwd = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
            $masterkey = New-DbaDbMasterKey -SqlInstance $global:instance2 -Database master -SecurePassword $passwd -Confirm:$false -ErrorAction SilentlyContinue

            $newdbs = New-DbaDatabase -SqlInstance $global:instance2, $global:instance3 -Name dbatoolscopycred
            $null = New-DbaDbMasterKey -SqlInstance $global:instance2 -Database dbatoolscopycred -SecurePassword $passwd -Confirm:$false
            $certificateName2 = "Cert_$(Get-Random)"
            $null = New-DbaDbCertificate -SqlInstance $global:instance2 -Name $certificateName2 -Database dbatoolscopycred -Confirm:$false
        }

        AfterAll {
            $null = $newdbs | Remove-DbaDatabase -Confirm:$false -ErrorAction SilentlyContinue
            if ($masterKey) {
                $masterkey | Remove-DbaDbMasterKey -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        It "Successfully copies a certificate" -Skip {
            $passwd = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
            $paramscopydb = @{
                Source             = $global:instance2
                Destination        = $global:instance3
                EncryptionPassword = $passwd
                MasterKeyPassword  = $passwd
                Database           = "dbatoolscopycred"
                SharedPath         = $global:appveyorlabrepo
            }
            $results = Copy-DbaDbCertificate @paramscopydb -Confirm:$false | Where-Object SourceDatabase -eq dbatoolscopycred | Select-Object -First 1
            $results.Notes | Should -Be $null
            $results.Status | Should -Be "Successful"
            $results.SourceDatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $global:instance2 -Database dbatoolscopycred).ID
            $results.DestinationDatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $global:instance3 -Database dbatoolscopycred).ID

            Get-DbaDbCertificate -SqlInstance $global:instance3 -Database dbatoolscopycred -Certificate $certificateName2 | Should -Not -BeNullOrEmpty
        }
    }
}
