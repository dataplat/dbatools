#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Enable-DbaStartupProcedure" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Enable-DbaStartupProcedure
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "SqlCredential",
                "StartupProcedure",
                "EnableException"
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

Describe "Enable-DbaStartupProcedure" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.Instance2
        $random = Get-Random
        $startupProcName = "StartUpProc$random"
        $startupProc = "dbo.$startupProcName"
        $dbname = 'master'

        $null = $server.Query("CREATE PROCEDURE $startupProc AS Select 1", $dbname)
    }

    AfterAll {
        $null = $server.Query("DROP PROCEDURE $startupProc", $dbname)
    }

    Context "When enabling a startup procedure" {
        BeforeAll {
            $result = Enable-DbaStartupProcedure -SqlInstance $TestConfig.Instance2 -StartupProcedure $startupProc -Confirm:$false
        }

        It "Should return successful enable results" {
            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Enable"
            $result.Status | Should -Be $true
            $result.Note | Should -Be "Enable succeded"
        }
    }

    Context "When enabling an already enabled procedure" {
        BeforeAll {
            $result = Enable-DbaStartupProcedure -SqlInstance $TestConfig.Instance2 -StartupProcedure $startupProc -Confirm:$false
        }

        It "Should return already enabled status" {
            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Enable"
            $result.Status | Should -Be $false
            $result.Note | Should -Be "Action Enable already performed"
        }
    }

    Context "When enabling a non-existent procedure" {
        BeforeAll {
            $result = Enable-DbaStartupProcedure -SqlInstance $TestConfig.Instance2 -StartupProcedure "Unknown.NotHere" -Confirm:$false
        }

        It "Should return null" {
            $result | Should -BeNull
        }
    }

    Context "When using an invalid procedure name format" {
        BeforeAll {
            $result = Enable-DbaStartupProcedure -SqlInstance $TestConfig.Instance2 -StartupProcedure "Four.Part.Schema.Name" -Confirm:$false
        }

        It "Should return null" {
            $result | Should -BeNull
        }
    }
}
