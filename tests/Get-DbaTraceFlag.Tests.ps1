#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaTraceFlag",
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
                "TraceFlag",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Verifying TraceFlag output" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $safeTraceFlag = 3226
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $startingTfs = @( $server.Query("DBCC TRACESTATUS(-1)") )
            $startingTfsCount = $startingTfs.Count

            if ($startingTfs.TraceFlag -notcontains $safeTraceFlag) {
                $server.Query("DBCC TRACEON($safeTraceFlag,-1) WITH NO_INFOMSGS")
                $startingTfsCount++
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if ($startingTfs.TraceFlag -notcontains $safeTraceFlag) {
                $server.Query("DBCC TRACEOFF($safeTraceFlag,-1)")
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Has the right default properties" {
            $expectedProps = "ComputerName", "InstanceName", "SqlInstance", "TraceFlag", "Global", "Status"
            $results = @( )
            $results += Get-DbaTraceFlag -SqlInstance $TestConfig.InstanceSingle
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Returns filtered results" {
            $results = Get-DbaTraceFlag -SqlInstance $TestConfig.InstanceSingle -TraceFlag $safeTraceFlag
            $results.TraceFlag.Count | Should -Be 1
            $results.TraceFlag | Should -Be $safeTraceFlag
            $results.Status | Should -Be 1
        }

        It "Returns all TFs" {
            $results = Get-DbaTraceFlag -SqlInstance $TestConfig.InstanceSingle
            #$results.TraceFlag.Count | Should -Be $startingTfsCount
            $results.TraceFlag | Should -Be $safeTraceFlag
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $safeTraceFlag = 3226
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            if (-not ($server.Query("DBCC TRACESTATUS(-1)") | Where-Object TraceFlag -eq $safeTraceFlag)) {
                $server.Query("DBCC TRACEON($safeTraceFlag,-1) WITH NO_INFOMSGS")
            }
            $result = Get-DbaTraceFlag -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $server.Query("DBCC TRACEOFF($safeTraceFlag,-1)")
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'TraceFlag',
                'Global',
                'Status'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has Session property available via Select-Object" {
            $result[0].PSObject.Properties.Name | Should -Contain 'Session' -Because "Session property should be accessible even though excluded from default view"
        }

        It "Has ComputerName property" {
            $result[0].PSObject.Properties.Name | Should -Contain 'ComputerName'
        }

        It "Has InstanceName property" {
            $result[0].PSObject.Properties.Name | Should -Contain 'InstanceName'
        }

        It "Has SqlInstance property" {
            $result[0].PSObject.Properties.Name | Should -Contain 'SqlInstance'
        }

        It "Has TraceFlag property" {
            $result[0].PSObject.Properties.Name | Should -Contain 'TraceFlag'
        }

        It "Has Global property" {
            $result[0].PSObject.Properties.Name | Should -Contain 'Global'
        }

        It "Has Status property" {
            $result[0].PSObject.Properties.Name | Should -Contain 'Status'
        }
    }
}