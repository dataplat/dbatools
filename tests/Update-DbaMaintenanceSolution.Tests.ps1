param($ModuleName = 'dbatools')

Describe "Update-DbaMaintenanceSolution" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Update-DbaMaintenanceSolution
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have Solution parameter" {
            $CommandUnderTest | Should -HaveParameter Solution
        }
        It "Should have LocalFile parameter" {
            $CommandUnderTest | Should -HaveParameter LocalFile
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            # Setup code for all tests in this context
            $server = Connect-DbaInstance -SqlInstance $global:instance1
        }

        It "Updates the maintenance solution" {
            $result = Update-DbaMaintenanceSolution -SqlInstance $global:instance1 -Database master
            $result | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be 'master'
            $result.Status | Should -Be 'Updated'
        }

        It "Throws an exception when an invalid database is specified" {
            { Update-DbaMaintenanceSolution -SqlInstance $global:instance1 -Database 'InvalidDB' -EnableException } | Should -Throw
        }

        It "Updates only specified solutions" {
            $result = Update-DbaMaintenanceSolution -SqlInstance $global:instance1 -Database master -Solution 'IndexOptimize'
            $result | Should -Not -BeNullOrEmpty
            $result.Solution | Should -Be 'IndexOptimize'
        }

        It "Uses a local file when specified" {
            $localFile = "TestDrive:\MaintenanceSolution.sql"
            Set-Content -Path $localFile -Value "SELECT 1 AS TestColumn"
            $result = Update-DbaMaintenanceSolution -SqlInstance $global:instance1 -Database master -LocalFile $localFile
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be 'Updated'
        }
    }
}
