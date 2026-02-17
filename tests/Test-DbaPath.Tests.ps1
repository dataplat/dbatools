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
        $trueTest = (Get-DbaDbFile -SqlInstance $TestConfig.InstanceMulti1 -Database master)[0].PhysicalName
        if ($trueTest.Length -eq 0) {
            $setupFailed = $true
        } else {
            $setupFailed = $false
        }
        $falseTest = "B:\FloppyDiskAreAwesome"
        $trueTestPath = [System.IO.Path]::GetDirectoryName($trueTest)
    }

    Context "Command actually works" {
        It "Should only return true if the path IS accessible to the instance" {
            $result = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path $trueTest
            $result | Should -Be $true
        }

        It "Should only return false if the path IS NOT accessible to the instance" {
            $result = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path $falseTest
            $result | Should -Be $false
        }

        It "Should return multiple results when passed multiple paths" {
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path $trueTest, $falseTest -OutVariable "global:dbatoolsciOutput"
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -Be $true
            ($results | Where-Object FilePath -eq $falseTest).FileExists | Should -Be $false
        }

        It "Should return multiple results when passed multiple instances" {
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Path $falseTest
            foreach ($result in $results) {
                $result.FileExists | Should -Be $false
            }
            ($results.SqlInstance | Sort-Object -Unique).Count | Should -Be 2
        }

        It "Should return PSCustomObject results when passed an array (even with one path)" {
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path @($trueTest)
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -Be $true
        }

        It "Should return PSCustomObject results indicating if the path is a file or a directory" {
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path @($trueTest, $trueTestPath)
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -Be $true
            ($results | Where-Object FilePath -eq $trueTestPath).FileExists | Should -Be $true
            ($results | Where-Object FilePath -eq $trueTest).IsContainer | Should -Be $false
            ($results | Where-Object FilePath -eq $trueTestPath).IsContainer | Should -Be $true
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "SqlInstance",
                "InstanceName",
                "ComputerName",
                "FilePath",
                "FileExists",
                "IsContainer"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Boolean|PSCustomObject"
        }
    }
}