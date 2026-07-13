#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaConnection",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "returns the proper transport" {
        It "returns a valid AuthScheme" {
            $results = Get-DbaConnection -SqlInstance $TestConfig.InstanceSingle
            # Session-less transport connections (for example the AG/HADR endpoint links on
            # an availability group primary) report auth_scheme "(Unknown)"; the auth-scheme
            # contract only applies to authenticated sessions.
            $sessionResults = @($results | Where-Object SessionId)
            $sessionResults.Count | Should -BeGreaterThan 0
            foreach ($result in $sessionResults) {
                $result.AuthScheme | Should -BeIn "NTLM", "Kerberos", "SQL"
            }
        }
    }
}