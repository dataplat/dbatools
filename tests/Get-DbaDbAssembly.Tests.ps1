param($ModuleName = 'dbatools')

Describe "Get-DbaDbAssembly" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbAssembly
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Gets the Db Assembly" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $results = Get-DbaDbAssembly -SqlInstance $global:instance2 | Where-Object { $_.parent.name -eq 'master' }
            $masterDb = Get-DbaDatabase -SqlInstance $global:instance2 -Database master
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
            $results.DatabaseId | Should -Be $masterDb.Id
        }

        It "Should have a name of Microsoft.SqlServer.Types" {
            $results.name | Should -Be "Microsoft.SqlServer.Types"
        }

        It "Should have an owner of sys" {
            $results.owner | Should -Be "sys"
        }

        It "Should have a version matching the instance" {
            $results.Version | Should -Be $masterDb.assemblies.Version
        }
    }
}
