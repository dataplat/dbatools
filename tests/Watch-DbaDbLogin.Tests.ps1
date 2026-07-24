#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Watch-DbaDbLogin",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Database",
                "Table",
                "SqlCredential",
                "SqlCms",
                "ServersFromFile",
                "InputObject",
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

        $random = Get-Random

        $testFile = "$($TestConfig.Temp)\Servers_$random.txt"
        $failureFile = "$($TestConfig.Temp)\Servers_unreachable_$random.txt"

        $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Out-File $testFile
        $TestConfig.InstanceUnreachable | Out-File $failureFile

        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2

        $null = Add-DbaRegServer -SqlInstance $TestConfig.InstanceMulti1 -ServerName $TestConfig.InstanceMulti2 -Name "dbatoolsci_instance_$random"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaRegServer -SqlInstance $TestConfig.InstanceMulti1 | Remove-DbaRegServer
        Remove-Item -Path $testFile, $failureFile

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        # We can only test that the command does not write any warning.
        # A real test would need a very complex setup.

        It "ServersFromFile" {
            Watch-DbaDbLogin -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -ServersFromFile $testFile
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Pipeline of instances" {
            $server1, $server2 | Watch-DbaDbLogin -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb
            $WarnVar | Should -BeNullOrEmpty
        }

        It "ServersFromCMS" {
            Watch-DbaDbLogin -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -SqlCms $TestConfig.InstanceMulti1
            $WarnVar | Should -BeNullOrEmpty
        }

        It "preserves the validation warning and silent error" {
            $validationWarnings = @()
            $expectedMessage = "You must specify a server list source using -SqlCms or -ServersFromFile or pipe in connected instances. See the command documentation and examples for more details."
            $errorCountBefore = $Error.Count

            Watch-DbaDbLogin -WarningVariable validationWarnings

            $validationWarnings.Count | Should -Be 1
            $validationWarnings[0].ToString().EndsWith("[Watch-DbaDbLogin] $expectedMessage") | Should -BeTrue
            # Characterization (compiled cmdlet, accepted divergence): the legacy function left its
            # self-swallowed Stop-Function record (FQID dbatools_Watch-DbaDbLogin) in the caller's
            # $Error; under the test harness defaults the compiled cmdlet's hop bookkeeping removes
            # it, so no new record survives here (ruled permissible engine leakage by the opus
            # review, migration/logs/opus-review-20260715-watch-dbadblogin). Outside the harness
            # the record IS present with the compiled FQID "dbatools_Watch-DbaDbLogin,Stop-Function"
            # (probe: migration/tools/Probe-WatchDbaDbLoginErrorState.ps1). Pin the harness contract
            # so the $Error surface is asserted rather than ignored.
            $Error.Count | Should -Be $errorCountBefore
        }

        It "preserves the validation warning before an EnableException error" {
            $validationWarnings = @()
            $expectedMessage = "You must specify a server list source using -SqlCms or -ServersFromFile or pipe in connected instances. See the command documentation and examples for more details."
            $caught = $null

            try {
                Watch-DbaDbLogin -EnableException -ErrorAction Stop -WarningVariable validationWarnings
            } catch {
                $caught = $_
            }

            $validationWarnings.Count | Should -Be 1
            $validationWarnings[0].ToString().EndsWith("[Watch-DbaDbLogin] $expectedMessage") | Should -BeTrue
            $caught.Exception.GetType().FullName | Should -Be "System.Exception"
            $caught.FullyQualifiedErrorId | Should -Be "dbatools_Watch-DbaDbLogin"
            $caught.Exception.Message | Should -Be $expectedMessage
        }

    }

    Context "Unreachable source" {
        BeforeAll {
            # Scoped to this Context alone, never the whole file: the legs above make real
            # connections and would turn flaky on a slow guest under a 1-second fuse. The pin is
            # needed because the unreachable endpoint is only refused instantly where the port is
            # CLOSED - where it is firewalled the packet is dropped and the leg waits out the
            # 15-second default instead. Restoring in AfterAll is mandatory, the setting being
            # process-wide.
            $previousConnectTimeout = Get-DbatoolsConfigValue -FullName sql.connection.timeout
            Set-DbatoolsConfig -FullName sql.connection.timeout -Value 1
        }
        AfterAll {
            Set-DbatoolsConfig -FullName sql.connection.timeout -Value $previousConnectTimeout
        }

        It "preserves nested and outer warnings for an unreachable source" {
            $sourceWarnings = @()

            $splatWatchFailure = @{
                SqlInstance     = $TestConfig.InstanceMulti1
                Database        = "tempdb"
                ServersFromFile = $failureFile
                WarningVariable = "sourceWarnings"
            }
            $result = @(Watch-DbaDbLogin @splatWatchFailure)

            $result.Count | Should -Be 0
            $sourceWarnings.Count | Should -Be 2
            $sourceWarnings[0].ToString() | Should -Match ([regex]::Escape("[Connect-DbaInstance] Failure | Error connecting to [$($TestConfig.InstanceUnreachable)]:"))
            $sourceWarnings[1].ToString() | Should -Match ([regex]::Escape("[Watch-DbaDbLogin] Failure |"))
        }
    }
}
