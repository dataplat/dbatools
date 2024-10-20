param($ModuleName = 'dbatools')

Describe "New-DbaSsisCatalog" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaSsisCatalog
        }

        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Credential",
                "SecurePassword",
                "SsisCatalog",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
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
