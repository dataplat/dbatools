#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDatabase",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaDatabase.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "InputObject",
                "AutoClose",
                "AutoCreateStatistics",
                "AutoShrink",
                "AutoUpdateStatistics",
                "PageVerify",
                "TargetRecoveryTime",
                "RollbackImmediate",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Exposes the boolean options as switches, not [bool] (dbatools house style)" {
            foreach ($switchName in "AutoClose", "AutoCreateStatistics", "AutoShrink", "AutoUpdateStatistics", "RollbackImmediate") {
                (Get-Command $CommandName).Parameters[$switchName].ParameterType.Name | Should -Be "SwitchParameter"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        $db1Name = "dbatoolscli_db1_$random"
        $db2Name = "dbatoolscli_db2_$random"

        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $db1Name, $db2Name

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $db1Name, $db2Name -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits the designed ShouldProcess string and changes nothing" {
            # -WhatIf must show the operation AND leave the option untouched. WhatIf text is
            # HOST-DIRECT: *>&1 / 6>&1 capture nothing in-process, so a transcript is the reliable
            # in-Pester capture.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_whatif_$random.txt"
            $splatWhatIf = @{
                SqlInstance = $InstanceSingle
                Database    = $db1Name
                AutoShrink  = $true
                WhatIf      = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Set-DbaDatabase @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $InstanceSingle.DomainInstanceName
                $expectedAction = "Altering database $db1Name"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAction`" on target `"$expectedTarget`""))
            } finally {
                # Stop-Transcript writes to the error stream when the host is no longer transcribing,
                # and Pester counts that as a failure - swallow it in a catch instead.
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and the side effect did NOT happen.
            (Get-DbaDatabase -SqlInstance $InstanceSingle -Database $db1Name).AutoShrink | Should -Be $false
        }
    }

    Context "Command behavior" {
        It "Sets a single option via -SqlInstance and leaves unbound options untouched" {
            # AutoShrink defaults false and AutoUpdateStatisticsEnabled defaults true on a new db.
            # Setting ONLY -AutoShrink must not disturb the statistics option - each option is
            # dirty-gated on being bound.
            $splatShrink = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                AutoShrink      = $true
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDatabase @splatShrink
            $result.AutoShrink | Should -Be $true
            # Decoration parity with Get-DbaDatabase so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty

            $readBack = Get-DbaDatabase -SqlInstance $InstanceSingle -Database $db1Name
            $readBack.AutoShrink | Should -Be $true
            $readBack.AutoUpdateStatisticsEnabled | Should -Be $true
        }

        It "Honours the explicit -AutoShrink:`$false form (switch tri-state)" {
            # A switch alone cannot say 'set to false'; -AutoShrink:$false must turn it back off.
            $splatOff = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                AutoShrink      = $false
                EnableException = $true
                Confirm         = $false
            }
            $null = Set-DbaDatabase @splatOff
            (Get-DbaDatabase -SqlInstance $InstanceSingle -Database $db1Name).AutoShrink | Should -Be $false
        }

        It "Sets TargetRecoveryTime (seconds) and PageVerify" {
            $splatOptions = @{
                SqlInstance        = $InstanceSingle
                Database           = $db1Name
                TargetRecoveryTime = 120
                PageVerify         = "TornPageDetection"
                EnableException    = $true
                Confirm            = $false
            }
            $null = Set-DbaDatabase @splatOptions
            $readBack = Get-DbaDatabase -SqlInstance $InstanceSingle -Database $db1Name
            $readBack.TargetRecoveryTime | Should -Be 120
            $readBack.PageVerify | Should -Be "TornPageDetection"
        }

        It "Applies an option with -RollbackImmediate" {
            # -RollbackImmediate selects the Alter(TerminationClause.RollbackTransactionsImmediately)
            # overload (WITH ROLLBACK IMMEDIATE). The change still lands.
            $splatRollback = @{
                SqlInstance       = $InstanceSingle
                Database          = $db1Name
                AutoCreateStatistics = $false
                RollbackImmediate = $true
                EnableException   = $true
                Confirm           = $false
            }
            $null = Set-DbaDatabase @splatRollback
            (Get-DbaDatabase -SqlInstance $InstanceSingle -Database $db1Name).AutoCreateStatisticsEnabled | Should -Be $false
        }

        It "Processes multiple piped databases (N in, N out) and changes each on the server" {
            # Mandatory multi-record piped leg fed by the getCounterpart. Both databases must come
            # back and both must actually change server-side - read back independently.
            $results = Get-DbaDatabase -SqlInstance $InstanceSingle -Database $db1Name, $db2Name |
                Set-DbaDatabase -AutoUpdateStatistics:$false -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            ($results.Name | Sort-Object -Unique) | Should -Be @($db1Name, $db2Name | Sort-Object)

            (Get-DbaDatabase -SqlInstance $InstanceSingle -Database $db1Name).AutoUpdateStatisticsEnabled | Should -Be $false
            (Get-DbaDatabase -SqlInstance $InstanceSingle -Database $db2Name).AutoUpdateStatisticsEnabled | Should -Be $false
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                AutoShrink      = $true
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaDatabase @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues on a negative TargetRecoveryTime without -EnableException" {
            $splatWarn = @{
                SqlInstance        = $InstanceSingle
                Database           = $db1Name
                TargetRecoveryTime = -5
                Confirm            = $false
                WarningAction      = "SilentlyContinue"
                WarningVariable    = "warnNeg"
            }
            $results = Set-DbaDatabase @splatWarn
            $warnNeg | Should -BeLike "*cannot be negative*"
            $results | Should -BeNullOrEmpty
        }

        It "Throws a terminating error on a negative TargetRecoveryTime with -EnableException" {
            $splatThrow = @{
                SqlInstance        = $InstanceSingle
                Database           = $db1Name
                TargetRecoveryTime = -5
                Confirm            = $false
                EnableException    = $true
            }
            { Set-DbaDatabase @splatThrow } | Should -Throw
        }
    }
}
