#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaKerberos",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "ComputerName",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should have SqlInstance in Instance parameter set" {
            $command = Get-Command $CommandName
            $instanceSet = $command.ParameterSets | Where-Object Name -eq "Instance"
            $instanceSet.Parameters.Name | Should -Contain "SqlInstance"
        }

        It "Should have ComputerName in Computer parameter set" {
            $command = Get-Command $CommandName
            $computerSet = $command.ParameterSets | Where-Object Name -eq "Computer"
            $computerSet.Parameters.Name | Should -Contain "ComputerName"
        }
    }
}

# The diagnostics need a domain (DC time/port checks, AD account queries, secure channel), so the
# workgroup AppVeyor host skips them; the lab runs the full battery. Diagnostics are read-only.
Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    Context "Instance diagnostics" {
        BeforeAll {
            $instanceResults = @(Test-DbaKerberos -SqlInstance $TestConfig.InstanceSingle -SqlCredential $TestConfig.SqlCred 3>$null)
        }

        It "Returns one object per check with the diagnostic shape" {
            $instanceResults.Count | Should -BeGreaterOrEqual 18
            foreach ($result in $instanceResults) {
                @($result.PSObject.Properties.Name) | Should -Be @("ComputerName", "InstanceName", "Check", "Category", "Status", "Details", "Remediation")
                $result.Status | Should -BeIn @("Pass", "Warning", "Fail")
                $result.Details | Should -Not -BeNullOrEmpty
                $result.Remediation | Should -Not -BeNullOrEmpty
            }
        }

        It "Runs the full instance check battery" {
            $checkNames = $instanceResults.Check
            foreach ($expected in @(
                    "SPN Registration",
                    "Time Synchronization (Client-Server)",
                    "Time Synchronization (Server-DC)",
                    "DNS Forward Lookup",
                    "DNS Reverse Lookup",
                    "Service Account Type",
                    "Account Lock Status",
                    "Delegation Settings",
                    "Current Authentication Scheme",
                    "Kerberos Port (TCP/88)",
                    "LDAP Port (TCP/389)",
                    "Kerberos-Kdc Port (TCP/464)",
                    "Kerberos Encryption Types",
                    "Computer Secure Channel",
                    "Hosts File",
                    "SQL Service Account Configuration",
                    "Network Protocol Configuration",
                    "Kerberos Ticket Cache"
                )) {
                $checkNames | Should -Contain $expected
            }
        }

        It "Carries the instance name on every result" {
            foreach ($result in $instanceResults) {
                $result.InstanceName | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context "Computer diagnostics" {
        BeforeAll {
            $computerResults = @(Test-DbaKerberos -ComputerName $TestConfig.InstanceSingle 3>$null)
        }

        It "Runs exactly the computer-level checks" {
            $computerResults.Count | Should -Be 12
            $computerResults.Check | Should -Not -Contain "Current Authentication Scheme"
            $computerResults.Check | Should -Not -Contain "Service Account Type"
            $computerResults.Check | Should -Not -Contain "Network Protocol Configuration"
        }

        It "Leaves InstanceName empty on every result" {
            foreach ($result in $computerResults) {
                $result.InstanceName | Should -BeNullOrEmpty
            }
        }
    }
}
