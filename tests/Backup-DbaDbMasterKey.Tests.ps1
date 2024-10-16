param($ModuleName = 'dbatools')

Describe "Backup-DbaDbMasterKey" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Backup-DbaDbMasterKey
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type String[] -Not -Mandatory
        }
        It "Should have SecurePassword as a non-mandatory parameter of type SecureString" {
            $CommandUnderTest | Should -HaveParameter SecurePassword -Type SecureString -Not -Mandatory
        }
        It "Should have Path as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory parameter of type Database[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $password = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
            $server = Connect-DbaInstance -SqlInstance $script:instance1
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
