param($ModuleName = 'dbatools')

Describe "Remove-DbaDbCertificate Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Importing any necessary modules or scripts
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandName = 'Remove-DbaDbCertificate'
            $command = Get-Command -Name $CommandName
        }

        It "Should have SqlInstance parameter" {
            $command | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }

        It "Should have SqlCredential parameter" {
            $command | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }

        It "Should have Database parameter" {
            $command | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }

        It "Should have Certificate parameter" {
            $command | Should -HaveParameter Certificate -Type String[] -Not -Mandatory
        }

        It "Should have InputObject parameter" {
            $command | Should -HaveParameter InputObject -Type Certificate[] -Not -Mandatory
        }

        It "Should have EnableException parameter" {
            $command | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }
}

Describe "Remove-DbaDbCertificate Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        $SkipTests = [Environment]::GetEnvironmentVariable('SkipRemoveDbaDbCertificateTests') -eq $true
    }

    Context "Can remove a database certificate" -Skip:$SkipTests {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            if (-not (Get-DbaDbMasterKey -SqlInstance $server -Database master)) {
                $masterkey = New-DbaDbMasterKey -SqlInstance $server -Database master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }
            $newCertificate = New-DbaDbCertificate -SqlInstance $server -Confirm:$false
        }

        AfterAll {
            if ($masterKey) {
                $masterkey | Remove-DbaDbMasterKey -Confirm:$false
            }
        }

        It "Successfully removes database certificate in master" {
            $results = $newCertificate | Remove-DbaDbCertificate -Confirm:$false
            $results.Status | Should -Match 'Success'
        }
    }
}
