param($ModuleName = 'dbatools')

Describe "Backup-DbaDbMasterKey" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Backup-DbaDbMasterKey
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Mandatory:$false
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Mandatory:$false
        }
        It "Should have SecurePassword as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SecurePassword -Mandatory:$false
        }
        It "Should have Path as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $password = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            if (-not (Get-DbaDbMasterKey -SqlInstance $server -Database tempdb)) {
                $null = New-DbaDbMasterKey -SqlInstance $server -Database tempdb -Password $password -Confirm:$false
            }
        }

        AfterAll {
            $null = Get-DbaDbMasterKey -SqlInstance $server -Database tempdb | Remove-DbaDbMasterKey -Confirm:$false
        }

        It "backs up the db master key" {
            $results = Backup-DbaDbMasterKey -SqlInstance $server -Database tempdb -Password $password -Confirm:$false
            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false

            $results.Database | Should -Be 'tempdb'
            $results.Status | Should -Be "Success"
        }

        It "returns the correct Database ID" {
            $results = Backup-DbaDbMasterKey -SqlInstance $server -Database tempdb -Password $password -Confirm:$false
            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false

            $results.DatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $server -Database tempdb).ID
        }
    }
}
