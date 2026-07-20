#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaLoginInGroup",
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
                "Login",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Read-only enumeration of the Windows-group members that map to SQL logins - no server state
        # is changed, so a live instance is all that is needed. Membership data is domain-dependent:
        # a lab with no Windows-group logins returns nothing, and the shape assertion then skips
        # (harness-honest) rather than fabricating data. try/finally restores the EnableException
        # default to its pre-suite state (existence AND value) even if the enumeration throws.
        $hadEnableException = $PSDefaultParameterValues.ContainsKey("*-Dba*:EnableException")
        if ($hadEnableException) { $priorEnableException = $PSDefaultParameterValues["*-Dba*:EnableException"] }
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        try {
            $results = Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle
        } finally {
            if ($hadEnableException) {
                $PSDefaultParameterValues["*-Dba*:EnableException"] = $priorEnableException
            } else {
                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            }
        }
    }

    Context "Enumerating Windows-group logins on a live instance" {
        It "Runs against the instance without throwing" {
            # Environment-independent: the enumeration completing (empty or not) is the assertion;
            # actual membership is domain-dependent and covered by the shape test below when present.
            { Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle -EnableException } | Should -Not -Throw
        }

        It "Returns objects carrying exactly the documented property set" {
            if ($null -eq $results) {
                Set-ItResult -Skipped -Because "no Windows-group SQL logins on $($TestConfig.InstanceSingle) to enumerate"
                return
            }
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "Login", "DisplayName", "MemberOf", "ParentADGroupLogin")
            # Compare-Object catches both missing AND extra (undocumented) properties.
            Compare-Object -ReferenceObject $expectedProps -DifferenceObject ($results | Select-Object -First 1).PSObject.Properties.Name | Should -BeNullOrEmpty
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}
