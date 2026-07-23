#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbMailProfile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaDbMailProfile.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Profile",
                "Description",
                "NewName",
                "InputObject",
                "AddAccount",
                "AccountSequence",
                "RemoveAccount",
                "AddPrincipal",
                "RemovePrincipal",
                "IsDefaultForPrincipal",
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
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        if ((Get-DbaSpConfigure -SqlInstance $server -Name "Database Mail XPs").RunningValue -ne 1) {
            Set-DbaSpConfigure -SqlInstance $server -Name "Database Mail XPs" -Value 1
        }

        # Two mail accounts to associate with profiles - one is enough for most legs, the second proves the
        # append-after-current-maximum sequence behaviour when -AccountSequence is not bound.
        $mailAccount1 = "dbatoolsci_mpacct1_$random"
        $mailAccount2 = "dbatoolsci_mpacct2_$random"
        foreach ($accountName in @($mailAccount1, $mailAccount2)) {
            $splatAccount = @{
                SqlInstance  = $server
                Account      = $accountName
                EmailAddress = "$accountName@dbatools.net"
                DisplayName  = $accountName
            }
            $null = New-DbaDbMailAccount @splatAccount
        }

        # Each behavioral leg gets its OWN profile so the tests do not couple through shared profile state.
        $profileDesc = "dbatoolsci_mpdesc_$random"
        $profileWhatIf = "dbatoolsci_mpwhatif_$random"
        $profileRename = "dbatoolsci_mprename_$random"
        $profileRenameNew = "dbatoolsci_mprenamed_$random"
        $profileAccount = "dbatoolsci_mpaccount_$random"
        $profilePrincipal = "dbatoolsci_mpprincipal_$random"
        $profilePipe1 = "dbatoolsci_mppipe1_$random"
        $profilePipe2 = "dbatoolsci_mppipe2_$random"
        $allProfiles = @($profileDesc, $profileWhatIf, $profileRename, $profileRenameNew, $profileAccount, $profilePrincipal, $profilePipe1, $profilePipe2)

        foreach ($profileName in @($profileDesc, $profileWhatIf, $profileRename, $profileAccount, $profilePrincipal, $profilePipe1, $profilePipe2)) {
            $null = New-DbaDbMailProfile -SqlInstance $server -Profile $profileName
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDbMailProfile -SqlInstance $server -Profile $allProfiles -ErrorAction SilentlyContinue
        foreach ($accountName in @($mailAccount1, $mailAccount2)) {
            $server.Query("EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$accountName';")
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Gates the alter and changes nothing" {
            # Alter executes immediately via ExecuteNonQuery, so WhatIf must gate it and leave the profile
            # untouched. The distinguishing assertion is that the side effect did NOT happen.
            $splatWhatIf = @{
                SqlInstance = $server
                Profile     = $profileWhatIf
                Description = "should-not-land"
                WhatIf      = $true
            }
            Set-DbaDbMailProfile @splatWhatIf

            # The side effect did NOT happen: the description is still empty.
            $unchanged = Get-DbaDbMailProfile -SqlInstance $server -Profile $profileWhatIf
            $unchanged.Description | Should -BeNullOrEmpty
        }
    }

    Context "Command behavior" {
        It "Sets the description and re-emits the decorated object" {
            $splatDesc = @{
                SqlInstance     = $server
                Profile         = $profileDesc
                Description     = "updated by Set-DbaDbMailProfile"
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDbMailProfile @splatDesc
            $result.Description | Should -Be "updated by Set-DbaDbMailProfile"
            # Decoration parity with Get-DbaDbMailProfile so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            # MailAccount is a synthesized note property, not an SMO property-bag entry.
            $result.PSObject.Properties.Name | Should -Contain "MailAccount"
            # Read back independently.
            $readBack = Get-DbaDbMailProfile -SqlInstance $server -Profile $profileDesc
            $readBack.Description | Should -Be "updated by Set-DbaDbMailProfile"
        }

        It "Renames the profile" {
            $splatRename = @{
                SqlInstance     = $server
                Profile         = $profileRename
                NewName         = $profileRenameNew
                EnableException = $true
                Confirm         = $false
            }
            $null = Set-DbaDbMailProfile @splatRename
            ((Get-DbaDbMailProfile -SqlInstance $server -Profile $profileRenameNew).Name | Select-Object -Unique) | Should -Be $profileRenameNew
            Get-DbaDbMailProfile -SqlInstance $server -Profile $profileRename | Should -BeNullOrEmpty
        }

        It "Adds accounts with an explicit and an appended failover sequence, then removes one" {
            # -AccountSequence carries the failover order; the first added account takes it, later accounts
            # increment. An account added WITHOUT -AccountSequence appends after the current maximum.
            $addFirst = Set-DbaDbMailProfile -SqlInstance $server -Profile $profileAccount -AddAccount $mailAccount1 -AccountSequence 5 -Confirm:$false -EnableException
            $addFirst.MailAccount | Should -Contain $mailAccount1
            $profAfterFirst = Get-DbaDbMailProfile -SqlInstance $server -Profile $profileAccount | Select-Object -First 1
            $row1 = @($profAfterFirst.EnumAccounts().Rows) | Where-Object AccountName -eq $mailAccount1
            [int]$row1.SequenceNumber | Should -Be 5

            $addSecond = Set-DbaDbMailProfile -SqlInstance $server -Profile $profileAccount -AddAccount $mailAccount2 -Confirm:$false -EnableException
            $addSecond.MailAccount | Should -Contain $mailAccount2
            $profAfterSecond = Get-DbaDbMailProfile -SqlInstance $server -Profile $profileAccount | Select-Object -First 1
            $row2 = @($profAfterSecond.EnumAccounts().Rows) | Where-Object AccountName -eq $mailAccount2
            [int]$row2.SequenceNumber | Should -Be 6

            $null = Set-DbaDbMailProfile -SqlInstance $server -Profile $profileAccount -RemoveAccount $mailAccount1 -Confirm:$false -EnableException
            $profAfterRemove = Get-DbaDbMailProfile -SqlInstance $server -Profile $profileAccount | Select-Object -First 1
            @($profAfterRemove.EnumAccounts().Rows).AccountName | Should -Not -Contain $mailAccount1
        }

        It "Adds and then removes a principal grant" {
            $null = Set-DbaDbMailProfile -SqlInstance $server -Profile $profilePrincipal -AddPrincipal "public" -IsDefaultForPrincipal -Confirm:$false -EnableException
            @((Get-DbaDbMailProfile -SqlInstance $server -Profile $profilePrincipal).EnumPrincipals().Rows).Count | Should -BeGreaterThan 0

            $null = Set-DbaDbMailProfile -SqlInstance $server -Profile $profilePrincipal -RemovePrincipal "public" -Confirm:$false -EnableException
            @((Get-DbaDbMailProfile -SqlInstance $server -Profile $profilePrincipal).EnumPrincipals().Rows).Count | Should -Be 0
        }

        It "Processes multiple piped profiles and resolves each record's own parent (N in, N out)" {
            # Multi-record piped leg. Two distinct profiles piped in must both come back altered, each
            # resolving its own parent server.
            $results = Get-DbaDbMailProfile -SqlInstance $server -Profile $profilePipe1, $profilePipe2 |
                Set-DbaDbMailProfile -Description "piped update" -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            ($results.Description | Sort-Object -Unique) | Should -Be "piped update"
            ($results.Name | Sort-Object) | Should -Be @($profilePipe1, $profilePipe2 | Sort-Object)

            # Read back independently - each profile's own description was changed.
            (Get-DbaDbMailProfile -SqlInstance $server -Profile $profilePipe1).Description | Should -Be "piped update"
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Profile         = $profileDesc
                Description     = "no target"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaDbMailProfile @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Rejects -IsDefaultForPrincipal without -AddPrincipal" {
            $splatDefaultAlone = @{
                SqlInstance           = $server
                Profile               = $profileDesc
                IsDefaultForPrincipal = $true
                Confirm               = $false
                WarningAction         = "SilentlyContinue"
                WarningVariable       = "warnDefaultAlone"
            }
            $results = Set-DbaDbMailProfile @splatDefaultAlone
            $warnDefaultAlone | Should -BeLike "*IsDefaultForPrincipal is only meaningful together with -AddPrincipal*"
            $results | Should -BeNullOrEmpty
        }

        It "Throws a terminating error with -EnableException" {
            $splatThrow = @{
                Profile         = $profileDesc
                Description     = "no target"
                Confirm         = $false
                EnableException = $true
            }
            { Set-DbaDbMailProfile @splatThrow } | Should -Throw
        }
    }
}
