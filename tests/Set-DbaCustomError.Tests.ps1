#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaCustomError",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaCustomError.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "MessageID",
                "Severity",
                "MessageText",
                "Language",
                "InputObject",
                "WithLog",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Exposes -WithLog as a switch, not [bool] (dbatools house style)" {
            (Get-Command $CommandName).Parameters["WithLog"].ParameterType.Name | Should -Be "SwitchParameter"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # Two distinct message IDs so the multi-record piped leg has independent objects to change.
        $messageId1 = 60000 + ($random % 5000)
        $messageId2 = $messageId1 + 1

        $null = New-DbaCustomError -SqlInstance $InstanceSingle -MessageID $messageId1 -Severity 16 -MessageText "original text 1"
        $null = New-DbaCustomError -SqlInstance $InstanceSingle -MessageID $messageId2 -Severity 16 -MessageText "original text 2"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaCustomError -SqlInstance $InstanceSingle -MessageID $messageId1 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-DbaCustomError -SqlInstance $InstanceSingle -MessageID $messageId2 -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits the designed ShouldProcess string and changes nothing" {
            # -WhatIf must show the operation AND leave the message untouched. WhatIf text is
            # HOST-DIRECT: *>&1 / 6>&1 capture nothing in-process, so a transcript is the reliable
            # in-Pester capture.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_whatif_ce_$random.txt"
            $splatWhatIf = @{
                SqlInstance = $InstanceSingle
                MessageID   = $messageId1
                Severity    = 20
                WhatIf      = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Set-DbaCustomError @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $InstanceSingle.DomainInstanceName
                $expectedAction = "Altering custom error $messageId1 in language us_english"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAction`" on target `"$expectedTarget`""))
            } finally {
                # Stop-Transcript writes to the error stream when the host is no longer transcribing,
                # and Pester counts that as a failure - swallow it in a catch instead.
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and the side effect did NOT happen: severity stays 16.
            (Get-DbaCustomError -SqlInstance $InstanceSingle | Where-Object ID -eq $messageId1).Severity | Should -Be 16
        }
    }

    Context "Command behavior" {
        It "Alters severity via -SqlInstance and leaves the text untouched" {
            # Setting ONLY -Severity must not disturb the message text - each property is dirty-gated
            # on being bound.
            $splatSeverity = @{
                SqlInstance     = $InstanceSingle
                MessageID       = $messageId1
                Severity        = 18
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaCustomError @splatSeverity
            $result.Severity | Should -Be 18
            $result.Text | Should -Be "original text 1"
            # Decoration parity with Get-DbaCustomError so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty

            $readBack = Get-DbaCustomError -SqlInstance $InstanceSingle | Where-Object ID -eq $messageId1
            $readBack.Severity | Should -Be 18
            $readBack.Text | Should -Be "original text 1"
        }

        It "Alters the message text via -MessageText" {
            $splatText = @{
                SqlInstance     = $InstanceSingle
                MessageID       = $messageId1
                MessageText     = "changed text 1"
                EnableException = $true
                Confirm         = $false
            }
            $null = Set-DbaCustomError @splatText
            (Get-DbaCustomError -SqlInstance $InstanceSingle | Where-Object ID -eq $messageId1).Text | Should -Be "changed text 1"
        }

        It "Toggles logging via -WithLog and honours the explicit -WithLog:`$false form (switch tri-state)" {
            $splatOn = @{
                SqlInstance     = $InstanceSingle
                MessageID       = $messageId1
                WithLog         = $true
                EnableException = $true
                Confirm         = $false
            }
            $null = Set-DbaCustomError @splatOn
            (Get-DbaCustomError -SqlInstance $InstanceSingle | Where-Object ID -eq $messageId1).IsLogged | Should -Be $true

            $splatOff = @{
                SqlInstance     = $InstanceSingle
                MessageID       = $messageId1
                WithLog         = $false
                EnableException = $true
                Confirm         = $false
            }
            $null = Set-DbaCustomError @splatOff
            (Get-DbaCustomError -SqlInstance $InstanceSingle | Where-Object ID -eq $messageId1).IsLogged | Should -Be $false
        }

        It "Processes multiple piped custom errors (N in, N out) and changes each on the server" {
            # Mandatory multi-record piped leg fed by the getCounterpart. Both messages must come back
            # and both must actually change server-side - read back independently.
            $results = Get-DbaCustomError -SqlInstance $InstanceSingle |
                Where-Object ID -in $messageId1, $messageId2 |
                Set-DbaCustomError -Severity 22 -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            ($results.ID | Sort-Object -Unique) | Should -Be @($messageId1, $messageId2 | Sort-Object)

            (Get-DbaCustomError -SqlInstance $InstanceSingle | Where-Object ID -eq $messageId1).Severity | Should -Be 22
            (Get-DbaCustomError -SqlInstance $InstanceSingle | Where-Object ID -eq $messageId2).Severity | Should -Be 22
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                MessageID       = $messageId1
                Severity        = 16
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaCustomError @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues when the language is not installed on the instance" {
            $splatBadLang = @{
                SqlInstance     = $InstanceSingle
                MessageID       = $messageId1
                Language        = "NotARealLanguage"
                Severity        = 16
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnLang"
            }
            $results = Set-DbaCustomError @splatBadLang
            $warnLang | Should -BeLike "*does not have the language NotARealLanguage installed*"
            $results | Should -BeNullOrEmpty
        }

        It "Throws a terminating error on a missing message ID with -EnableException" {
            $splatThrow = @{
                SqlInstance     = $InstanceSingle
                MessageID       = 50123
                Severity        = 16
                Confirm         = $false
                EnableException = $true
            }
            { Set-DbaCustomError @splatThrow } | Should -Throw
        }
    }
}
