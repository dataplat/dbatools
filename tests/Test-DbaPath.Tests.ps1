#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaPath",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $trueTest = (Get-DbaDbFile -SqlInstance $TestConfig.instance2 -Database master)[0].PhysicalName
        if ($trueTest.Length -eq 0) {
            $setupFailed = $true
        } else {
            $setupFailed = $false
        }
        $falseTest = "B:\FloppyDiskAreAwesome"
        $trueTestPath = [System.IO.Path]::GetDirectoryName($trueTest)
    }

    Context "Command actually works" {
        It "has failed setup" -Skip:(-not $setupFailed) {
            Set-TestInconclusive -message "Setup failed"
        }

        It "Should only return true if the path IS accessible to the instance" {
            $result = Test-DbaPath -SqlInstance $TestConfig.instance2 -Path $trueTest
            $result | Should -Be $true
        }

        It "Should only return false if the path IS NOT accessible to the instance" {
            $result = Test-DbaPath -SqlInstance $TestConfig.instance2 -Path $falseTest
            $result | Should -Be $false
        }

        It "Should return multiple results when passed multiple paths" {
            $results = Test-DbaPath -SqlInstance $TestConfig.instance2 -Path $trueTest, $falseTest
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -Be $true
            ($results | Where-Object FilePath -eq $falseTest).FileExists | Should -Be $false
        }

        It "Should return multiple results when passed multiple instances" {
            $results = Test-DbaPath -SqlInstance $TestConfig.instance2, $TestConfig.instance1 -Path $falseTest
            foreach ($result in $results) {
                $result.FileExists | Should -Be $false
            }
            ($results.SqlInstance | Sort-Object -Unique).Count | Should -Be 2
        }

        It "Should return PSCustomObject results when passed an array (even with one path)" {
            $results = Test-DbaPath -SqlInstance $TestConfig.instance2 -Path @($trueTest)
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -Be $true
        }

        It "Should return PSCustomObject results indicating if the path is a file or a directory" {
            $results = Test-DbaPath -SqlInstance $TestConfig.instance2 -Path @($trueTest, $trueTestPath)
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -Be $true
            ($results | Where-Object FilePath -eq $trueTestPath).FileExists | Should -Be $true
            ($results | Where-Object FilePath -eq $trueTest).IsContainer | Should -Be $false
            ($results | Where-Object FilePath -eq $trueTestPath).IsContainer | Should -Be $true
        }
    }
}