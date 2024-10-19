param($ModuleName = 'dbatools')

Describe "New-DbaSsisCatalog" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaSsisCatalog
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have SecurePassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecurePassword
        }
        It "Should have SsisCatalog as a parameter" {
            $CommandUnderTest | Should -HaveParameter SsisCatalog
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Catalog is added properly" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $database = "SSISDB"
            $db = Get-DbaDatabase -SqlInstance $ssisserver -Database $database
        }

        It "Creates the catalog when it doesn't exist" -Skip:($db -ne $null) {
            $password = ConvertTo-SecureString MyVisiblePassWord -AsPlainText -Force
            $results = New-DbaSsisCatalog -SqlInstance $ssisserver -SecurePassword $password -WarningAction SilentlyContinue -WarningVariable warn

            if ($warn -match "not running") {
                if (-not $env:APPVEYOR_REPO_BRANCH) {
                    Set-ItResult -Skipped -Because "SSIS is not running: $warn"
                }
            } else {
                $results.SsisCatalog | Should -Be $database
                $results.Created | Should -Be $true
            }
        }

        AfterAll {
            if ($db -eq $null) {
                Remove-DbaDatabase -Confirm:$false -SqlInstance $ssisserver -Database $database
            }
        }
    }
}
