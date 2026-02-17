#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDiskAllocation",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "NoSqlCheck",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        It "Should return a result" {
            $results = Test-DbaDiskAllocation -ComputerName $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            $results | Should -Not -Be $null
        }

        It "Should return a result not using sql" {
            $results = Test-DbaDiskAllocation -NoSqlCheck -ComputerName $TestConfig.InstanceSingle
            $results | Should -Not -Be $null
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
                "ComputerName",
                "DiskName",
                "DiskLabel",
                "BlockSize",
                "IsSqlDisk",
                "IsBestPractice"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name | Where-Object { $PSItem -notin "Server", "Name", "Label" }
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "DiskName",
                "DiskLabel",
                "BlockSize",
                "IsSqlDisk",
                "IsBestPractice"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}