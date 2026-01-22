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

    Context "Output Validation" {
        It "Returns Boolean when testing single path on single instance" {
            $result = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path $trueTest -EnableException
            $result | Should -BeOfType [System.Boolean]
        }

        It "Returns PSCustomObject when testing multiple paths" {
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path $trueTest, $falseTest -EnableException
            $results[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected properties for PSCustomObject output" {
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path $trueTest, $falseTest -EnableException
            $expectedProps = @(
                'SqlInstance',
                'InstanceName',
                'ComputerName',
                'FilePath',
                'FileExists',
                'IsContainer'
            )
            $actualProps = $results[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }

        It "Returns PSCustomObject when testing array input (even single path)" {
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path @($trueTest) -EnableException
            $results.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Returns PSCustomObject when testing multiple instances" {
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Path $falseTest -EnableException
            $results[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }
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
            $results = Test-DbaPath -SqlInstance $TestConfig.InstanceMulti1 -Path $trueTest, $falseTest
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
}