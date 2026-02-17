#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbccFreeCache",
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
                "InputValue",
                "NoInformationalMessages",
                "MarkInUseForRemoval",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $expectedProperties = @(
            "ComputerName",
            "InstanceName",
            "SqlInstance",
            "Operation",
            "Cmd",
            "Output"
        )
        $resultFreeSystemCache = Invoke-DbaDbccFreeCache -SqlInstance $TestConfig.InstanceSingle -Operation FreeSystemCache -OutVariable "global:dbatoolsciOutput"
    }

    Context "Validate standard output" {
        It "Should return all expected properties" {
            foreach ($property in $expectedProperties) {
                $resultFreeSystemCache.PSObject.Properties[$property] | Should -Not -BeNullOrEmpty
                $resultFreeSystemCache.PSObject.Properties[$property].Name | Should -Be $property
            }
        }
    }

    Context "Works correctly" {
        It "returns the right results for FREESYSTEMCACHE" {
            $resultFreeSystemCache.Operation | Should -Match "FREESYSTEMCACHE"
            $resultFreeSystemCache.Output | Should -Match "DBCC execution completed. If DBCC printed error messages, contact your system administrator."
        }

        It "returns the right results for FREESESSIONCACHE" {
            $resultFreeSessionCache = Invoke-DbaDbccFreeCache -SqlInstance $TestConfig.InstanceSingle -Operation FreeSessionCache
            $resultFreeSessionCache.Operation | Should -Match "FREESESSIONCACHE"
            $resultFreeSessionCache.Output | Should -Match "DBCC execution completed. If DBCC printed error messages, contact your system administrator."
        }

        It "returns the right results for FREEPROCCACHE" {
            $resultFreeProcCache = Invoke-DbaDbccFreeCache -SqlInstance $TestConfig.InstanceSingle -Operation FREEPROCCACHE
            $resultFreeProcCache.Operation | Should -Match "FREEPROCCACHE"
            $resultFreeProcCache.Output | Should -Match "DBCC execution completed. If DBCC printed error messages, contact your system administrator."
        }

        It "returns the right results for FREESESSIONCACHE and using NoInformationalMessages" {
            $resultNoInfo = Invoke-DbaDbccFreeCache -SqlInstance $TestConfig.InstanceSingle -Operation FreeSessionCache -NoInformationalMessages
            $resultNoInfo.Operation | Should -Match "FREESESSIONCACHE"
            $resultNoInfo.Output | Should -BeNullOrEmpty
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
                "InstanceName",
                "SqlInstance",
                "Operation",
                "Cmd",
                "Output"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}