#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentJobOwner",
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
                "Job",
                "ExcludeJob",
                "InputObject",
                "Login",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # A dedicated SQL login used as the non-default owner target. sa (login id 1) is the
        # dynamic default the command falls back to when -Login is omitted; capturing its name
        # lets the default-owner test assert exactly what the source computes. A WindowsGroup
        # login (if any exists on this instance) drives the rejection path.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $saLogin = ($server.Logins | Where-Object { $PSItem.Id -eq 1 }).Name
        $windowsGroupLogin = ($server.Logins | Where-Object { $PSItem.LoginType -eq "WindowsGroup" } | Select-Object -First 1).Name

        $ownerLogin = "dbatoolsci_owner_$(Get-Random)"
        $securePassword = ConvertTo-SecureString "dbatools.IO$(Get-Random)" -AsPlainText -Force
        $splatLogin = @{
            SqlInstance    = $TestConfig.InstanceSingle
            Login          = $ownerLogin
            SecurePassword = $securePassword
            Force          = $true
        }
        $null = New-DbaLogin @splatLogin

        # One job per test so the destructive owner changes never leak across tests (each
        # scenario owns its state and the suite stays order-independent).
        $jobSet = "dbatoolsci_jobowner_set_$(Get-Random)"
        $jobSkip = "dbatoolsci_jobowner_skip_$(Get-Random)"
        $jobInvalid = "dbatoolsci_jobowner_invalid_$(Get-Random)"
        $jobWhatIf = "dbatoolsci_jobowner_whatif_$(Get-Random)"
        $jobDefault = "dbatoolsci_jobowner_default_$(Get-Random)"
        $jobKeep = "dbatoolsci_jobowner_keep_$(Get-Random)"
        $jobExclude = "dbatoolsci_jobowner_excl_$(Get-Random)"
        $jobWinGroup = "dbatoolsci_jobowner_wingroup_$(Get-Random)"
        $allJobs = @($jobSet, $jobSkip, $jobInvalid, $jobWhatIf, $jobDefault, $jobKeep, $jobExclude, $jobWinGroup)

        foreach ($j in $allJobs) {
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $j
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        try {
            $splatGet = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $allJobs
                ErrorAction = "SilentlyContinue"
            }
            Get-DbaAgentJob @splatGet | Remove-DbaAgentJob -ErrorAction SilentlyContinue
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $ownerLogin -ErrorAction SilentlyContinue
        } finally {
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Setting the owner" {
        It "Sets the owner and returns the modified SMO job with Successful status" {
            $splatSet = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobSet
                Login       = $ownerLogin
            }
            $result = Set-DbaAgentJobOwner @splatSet
            $result | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.Job
            $result.Status | Should -Be "Successful"
            $result.Notes | Should -Be ""
            $result.OwnerLoginName | Should -Be $ownerLogin
            # the added connection-context note properties are always attached
            $result.PSObject.Properties.Name | Should -Contain "ComputerName"
            $result.PSObject.Properties.Name | Should -Contain "InstanceName"
            $result.PSObject.Properties.Name | Should -Contain "SqlInstance"
            # Alter() persisted the change, not just the in-memory object
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobSet).OwnerLoginName | Should -Be $ownerLogin
        }

        It "Skips a job whose owner already matches the target and leaves it unchanged" {
            # Establish the target owner first, then re-run: the second pass is the no-op path.
            $splatSkip = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobSkip
                Login       = $ownerLogin
            }
            $null = Set-DbaAgentJobOwner @splatSkip
            $result = Set-DbaAgentJobOwner @splatSkip
            $result.Status | Should -Be "Skipped"
            $result.Notes | Should -Be "Owner already set"
            $result.OwnerLoginName | Should -Be $ownerLogin
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobSkip).OwnerLoginName | Should -Be $ownerLogin
        }

        It "Falls back to the sa (login id 1) owner when -Login is omitted" {
            # Move it off sa first so the default path has an observable change to make.
            $splatOff = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobDefault
                Login       = $ownerLogin
            }
            $null = Set-DbaAgentJobOwner @splatOff
            $result = Set-DbaAgentJobOwner -SqlInstance $TestConfig.InstanceSingle -Job $jobDefault
            $result.Status | Should -Be "Successful"
            $result.OwnerLoginName | Should -Be $saLogin
            # persisted, not just mutated in memory
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobDefault).OwnerLoginName | Should -Be $saLogin
        }
    }

    Context "Invalid target" {
        It "Reports Failed for a login that does not exist and leaves the owner unchanged" {
            $before = (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobInvalid).OwnerLoginName
            $missingLogin = "dbatoolsci_nologin_$(Get-Random)"
            $splatMissing = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobInvalid
                Login       = $missingLogin
            }
            $result = Set-DbaAgentJobOwner @splatMissing
            $result.Status | Should -Be "Failed"
            $result.Notes | Should -Be "Login $missingLogin not valid"
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobInvalid).OwnerLoginName | Should -Be $before
        }

        It "Reports Failed for a WindowsGroup login and leaves the owner unchanged" {
            if (-not $windowsGroupLogin) {
                Set-ItResult -Skipped -Because "no WindowsGroup login is present on this instance"
                return
            }
            $before = (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobWinGroup).OwnerLoginName
            $splatWin = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobWinGroup
                Login       = $windowsGroupLogin
            }
            $result = Set-DbaAgentJobOwner @splatWin
            $result.Status | Should -Be "Failed"
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobWinGroup).OwnerLoginName | Should -Be $before
        }
    }

    Context "WhatIf" {
        It "Emits the job but does not change the owner under -WhatIf" {
            $before = (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobWhatIf).OwnerLoginName
            $splatWhatIf = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobWhatIf
                Login       = $ownerLogin
                WhatIf      = $true
            }
            $result = Set-DbaAgentJobOwner @splatWhatIf
            # the object is still emitted, but the Alter branch (and its Status assignment) is skipped
            $result | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.Job
            $result.Status | Should -BeNullOrEmpty
            $result.OwnerLoginName | Should -Be $before
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobWhatIf).OwnerLoginName | Should -Be $before
        }
    }

    Context "Job selection" {
        It "Honours -ExcludeJob so an excluded job is never touched" {
            $before = (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobExclude).OwnerLoginName
            $splatExclude = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = @($jobKeep, $jobExclude)
                ExcludeJob  = $jobExclude
                Login       = $ownerLogin
            }
            $result = Set-DbaAgentJobOwner @splatExclude
            $result.Name | Should -Be $jobKeep
            $result.Status | Should -Be "Successful"
            $result.OwnerLoginName | Should -Be $ownerLogin
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobKeep).OwnerLoginName | Should -Be $ownerLogin
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobExclude).OwnerLoginName | Should -Be $before
        }

        It "Selects all Local jobs when -Job is omitted" {
            # -WhatIf keeps this read-only across every local job on the instance while still
            # exercising the "all Local jobs, no non-Local" selection branch.
            $splatAll = @{
                SqlInstance = $TestConfig.InstanceSingle
                Login       = $ownerLogin
                WhatIf      = $true
            }
            $result = Set-DbaAgentJobOwner @splatAll
            $result.Name | Should -Contain $jobSet
            # the selection filter is JobType -eq Local, so nothing else should slip through
            $result.JobType | Where-Object { $PSItem -ne "Local" } | Should -BeNullOrEmpty
        }
    }
}
