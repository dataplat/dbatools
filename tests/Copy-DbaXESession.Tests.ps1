#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaXESession",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Destination",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "XeSession",
                "ExcludeXeSession",
                "Force",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables. They are available in all the It blocks.
        $global:sourceInstance      = $TestConfig.instance2
        $global:destinationInstance = $TestConfig.instance3
        $global:sessionName1        = "dbatoolsci_session1_$(Get-Random)"
        $global:sessionName2        = "dbatoolsci_session2_$(Get-Random)"
        $global:sessionName3        = "dbatoolsci_session3_$(Get-Random)"

        # Create the test XE sessions on the source instance
        $splatCreateSession1 = @{
            SqlInstance     = $global:sourceInstance
            Name            = $global:sessionName1
            StartupState    = "Off"
            EnableException = $true
        }
        $null = New-DbaXESession @splatCreateSession1

        $splatCreateSession2 = @{
            SqlInstance     = $global:sourceInstance
            Name            = $global:sessionName2
            StartupState    = "Off"
            EnableException = $true
        }
        $null = New-DbaXESession @splatCreateSession2

        $splatCreateSession3 = @{
            SqlInstance     = $global:sourceInstance
            Name            = $global:sessionName3
            StartupState    = "Off"
            EnableException = $true
        }
        $null = New-DbaXESession @splatCreateSession3

        # Start one session to test copying running sessions
        $null = Start-DbaXESession -SqlInstance $global:sourceInstance -Session $global:sessionName1 -EnableException

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Stop and remove sessions from source
        $null = Stop-DbaXESession -SqlInstance $global:sourceInstance -Session $global:sessionName1, $global:sessionName2, $global:sessionName3 -ErrorAction SilentlyContinue
        $null = Remove-DbaXESession -SqlInstance $global:sourceInstance -Session $global:sessionName1, $global:sessionName2, $global:sessionName3 -ErrorAction SilentlyContinue

        # Stop and remove sessions from destination
        $null = Stop-DbaXESession -SqlInstance $global:destinationInstance -Session $global:sessionName1, $global:sessionName2, $global:sessionName3 -ErrorAction SilentlyContinue
        $null = Remove-DbaXESession -SqlInstance $global:destinationInstance -Session $global:sessionName1, $global:sessionName2, $global:sessionName3 -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When copying all XE sessions" {
        It "Copies all sessions from source to destination" {
            $splatCopyAll = @{
                Source      = $global:sourceInstance
                Destination = $global:destinationInstance
                Force       = $true
            }
            $results = Copy-DbaXESession @splatCopyAll
            $results | Should -Not -BeNullOrEmpty
        }

        It "Verifies sessions exist on destination" {
            $destinationSessions = Get-DbaXESession -SqlInstance $global:destinationInstance
            $sessionNames = $destinationSessions.Name
            $global:sessionName1 | Should -BeIn $sessionNames
            $global:sessionName2 | Should -BeIn $sessionNames
            $global:sessionName3 | Should -BeIn $sessionNames
        }
    }

    Context "When copying specific XE sessions" {
        BeforeAll {
            # Remove sessions from destination for this test
            $null = Stop-DbaXESession -SqlInstance $global:destinationInstance -Session $global:sessionName1, $global:sessionName2 -ErrorAction SilentlyContinue
            $null = Remove-DbaXESession -SqlInstance $global:destinationInstance -Session $global:sessionName1, $global:sessionName2 -ErrorAction SilentlyContinue
        }

        It "Copies only specified sessions" {
            $splatCopySpecific = @{
                Source      = $global:sourceInstance
                Destination = $global:destinationInstance
                XeSession   = @($global:sessionName1, $global:sessionName2)
                Force       = $true
            }
            $results = Copy-DbaXESession @splatCopySpecific
            $results.Name | Should -Contain $global:sessionName1
            $results.Name | Should -Contain $global:sessionName2
            $results.Name | Should -Not -Contain $global:sessionName3
        }
    }

    Context "When excluding specific XE sessions" {
        BeforeAll {
            # Remove all test sessions from destination for this test
            $null = Stop-DbaXESession -SqlInstance $global:destinationInstance -Session $global:sessionName1, $global:sessionName2, $global:sessionName3 -ErrorAction SilentlyContinue
            $null = Remove-DbaXESession -SqlInstance $global:destinationInstance -Session $global:sessionName1, $global:sessionName2, $global:sessionName3 -ErrorAction SilentlyContinue
        }

        It "Excludes specified sessions from copy" {
            $splatCopyExclude = @{
                Source           = $global:sourceInstance
                Destination      = $global:destinationInstance
                ExcludeXeSession = $global:sessionName3
                Force            = $true
            }
            $results = Copy-DbaXESession @splatCopyExclude
            $copiedNames = $results | Where-Object Name -in @($global:sessionName1, $global:sessionName2, $global:sessionName3)
            $copiedNames.Name | Should -Contain $global:sessionName1
            $copiedNames.Name | Should -Contain $global:sessionName2
            $copiedNames.Name | Should -Not -Contain $global:sessionName3
        }
    }

    Context "When session already exists on destination" {
        BeforeAll {
            # Ensure session exists on destination for conflict test
            $splatEnsureExists = @{
                Source      = $global:sourceInstance
                Destination = $global:destinationInstance
                XeSession   = $global:sessionName1
                Force       = $true
            }
            $null = Copy-DbaXESession @splatEnsureExists
        }

        It "Warns when session exists without Force" {
            $splatCopyNoForce = @{
                Source          = $global:sourceInstance
                Destination     = $global:destinationInstance
                XeSession       = $global:sessionName1
                WarningVariable = "copyWarning"
                WarningAction   = "SilentlyContinue"
            }
            $null = Copy-DbaXESession @splatCopyNoForce
            $copyWarning | Should -Not -BeNullOrEmpty
        }

        It "Overwrites session when using Force" {
            # Stop the session on destination first
            $null = Stop-DbaXESession -SqlInstance $global:destinationInstance -Session $global:sessionName1 -ErrorAction SilentlyContinue

            $splatCopyForce = @{
                Source      = $global:sourceInstance
                Destination = $global:destinationInstance
                XeSession   = $global:sessionName1
                Force       = $true
            }
            $results = Copy-DbaXESession @splatCopyForce
            $results.Status | Should -Be "Successful"
        }
    }

    Context "When using WhatIf" {
        It "Does not copy sessions with WhatIf" {
            # Remove a session from destination to test WhatIf
            $null = Stop-DbaXESession -SqlInstance $global:destinationInstance -Session $global:sessionName2 -ErrorAction SilentlyContinue
            $null = Remove-DbaXESession -SqlInstance $global:destinationInstance -Session $global:sessionName2 -ErrorAction SilentlyContinue

            $splatCopyWhatIf = @{
                Source      = $global:sourceInstance
                Destination = $global:destinationInstance
                XeSession   = $global:sessionName2
                WhatIf      = $true
            }
            $null = Copy-DbaXESession @splatCopyWhatIf

            # Verify session was not copied
            $destinationSession = Get-DbaXESession -SqlInstance $global:destinationInstance -Session $global:sessionName2
            $destinationSession | Should -BeNullOrEmpty
        }
    }
}