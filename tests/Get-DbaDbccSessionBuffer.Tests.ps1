#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbccSessionBuffer",
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
                "Operation",
                "SessionId",
                "RequestId",
                "All",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
        $queryResult = $db.Query("SELECT top 10 object_id, @@Spid as MySpid FROM sys.objects")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Validate standard output for all databases" {
        BeforeAll {
            $propsInputBuffer = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SessionId",
                "EventType",
                "Parameters",
                "EventInfo"
            )
            $propsOutputBuffer = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SessionId",
                "Buffer",
                "HexBuffer"
            )
            $resultInputBuffer = Get-DbaDbccSessionBuffer -SqlInstance $TestConfig.InstanceSingle -Operation InputBuffer -All
            $resultOutputBuffer = Get-DbaDbccSessionBuffer -SqlInstance $TestConfig.InstanceSingle -Operation OutputBuffer -All
        }

        It "Returns results for InputBuffer" {
            $resultInputBuffer.Count | Should -BeGreaterThan 0
        }

        It "Returns results for OutputBuffer" {
            $resultOutputBuffer.Count | Should -BeGreaterThan 0
        }

        It "Should return property: <_> for InputBuffer" -ForEach $propsInputBuffer {
            $resultInputBuffer[0].PSObject.Properties[$PSItem].Name | Should -Be $PSItem
        }

        It "Should return property: <_> for OutputBuffer" -ForEach $propsOutputBuffer {
            $resultOutputBuffer[0].PSObject.Properties[$PSItem].Name | Should -Be $PSItem
        }
    }

    Context "Validate returns results for SessionId" {
        BeforeAll {
            $spid = $queryResult[0].MySpid
            $resultInputBuffer = Get-DbaDbccSessionBuffer -SqlInstance $TestConfig.InstanceSingle -Operation InputBuffer -SessionId $spid
            $resultOutputBuffer = Get-DbaDbccSessionBuffer -SqlInstance $TestConfig.InstanceSingle -Operation OutputBuffer -SessionId $spid
        }

        It "Returns results for InputBuffer with correct SessionId" {
            $resultInputBuffer.SessionId | Should -Be $spid
        }

        It "Returns results for OutputBuffer with correct SessionId" {
            $resultOutputBuffer.SessionId | Should -Be $spid
        }
    }

    Context "Output validation" {
        BeforeAll {
            $spidForOutput = $queryResult[0].MySpid
            $outputInputBuffer = Get-DbaDbccSessionBuffer -SqlInstance $TestConfig.InstanceSingle -Operation InputBuffer -SessionId $spidForOutput
            $outputOutputBuffer = Get-DbaDbccSessionBuffer -SqlInstance $TestConfig.InstanceSingle -Operation OutputBuffer -SessionId $spidForOutput
        }

        It "Returns output of type PSCustomObject for InputBuffer" {
            if (-not $outputInputBuffer) { Set-ItResult -Skipped -Because "no InputBuffer result to validate" }
            $outputInputBuffer[0] | Should -BeOfType [PSCustomObject]
        }

        It "Returns output of type PSCustomObject for OutputBuffer" {
            if (-not $outputOutputBuffer) { Set-ItResult -Skipped -Because "no OutputBuffer result to validate" }
            $outputOutputBuffer[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the correct properties for InputBuffer" {
            if (-not $outputInputBuffer) { Set-ItResult -Skipped -Because "no InputBuffer result to validate" }
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "SessionId", "EventType", "Parameters", "EventInfo")
            foreach ($prop in $expectedProps) {
                $outputInputBuffer[0].PSObject.Properties[$prop] | Should -Not -BeNullOrEmpty -Because "property '$prop' should exist on InputBuffer output"
            }
        }

        It "Has the correct properties for OutputBuffer" {
            if (-not $outputOutputBuffer) { Set-ItResult -Skipped -Because "no OutputBuffer result to validate" }
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "SessionId", "Buffer", "HexBuffer")
            foreach ($prop in $expectedProps) {
                $outputOutputBuffer[0].PSObject.Properties[$prop] | Should -Not -BeNullOrEmpty -Because "property '$prop' should exist on OutputBuffer output"
            }
        }

        It "Has the expected default display properties for OutputBuffer" {
            if (-not $outputOutputBuffer) { Set-ItResult -Skipped -Because "no OutputBuffer result to validate" }
            $defaultProps = $outputOutputBuffer[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "SessionId", "Buffer")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Does not include HexBuffer in default display properties for OutputBuffer" {
            if (-not $outputOutputBuffer) { Set-ItResult -Skipped -Because "no OutputBuffer result to validate" }
            $defaultProps = $outputOutputBuffer[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "HexBuffer" -Because "HexBuffer should not be in the default display set"
        }
    }
}