param($ModuleName = 'dbatools')

Describe "Copy-DbaDbCertificate" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaDbCertificate
        }
        $paramsList = @(
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
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramsList {
            $command | Should -HaveParameter $PSItem
        }
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
