#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaServerRole",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaServerRole.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "ServerRole",
                "Owner",
                "NewName",
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
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        $securePassword = ConvertTo-SecureString -String "securePassword1!" -AsPlainText -Force
        # A server-role owner must be a server login (or another server role).
        $ownerLoginName = "dbatoolscli_srowner_$random"
        $role1Name = "dbatoolscli_srole1_$random"
        $role2Name = "dbatoolscli_srole2_$random"
        $renameSourceName = "dbatoolscli_srrole_$random"
        $renameTargetName = "dbatoolscli_srrenamed_$random"

        New-DbaLogin -SqlInstance $InstanceSingle -Login $ownerLoginName -SecurePassword $securePassword
        New-DbaServerRole -SqlInstance $InstanceSingle -ServerRole $role1Name, $role2Name, $renameSourceName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaServerRole -SqlInstance $InstanceSingle -ServerRole $role1Name, $role2Name, $renameTargetName -Confirm:$false -ErrorAction SilentlyContinue
        Remove-DbaLogin -SqlInstance $InstanceSingle -Login $ownerLoginName -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits BOTH designed ShouldProcess strings and changes nothing" {
            # TWO shouldProcessTargets: the owner alter and the rename are separate statements, not
            # one atomic operation. WhatIf text is HOST-DIRECT so a transcript is the reliable capture.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_whatif_$random.txt"
            $splatWhatIf = @{
                SqlInstance = $InstanceSingle
                ServerRole  = $role2Name
                Owner       = $ownerLoginName
                NewName     = "dbatoolscli_neverapplied_$random"
                WhatIf      = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Set-DbaServerRole @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $InstanceSingle.DomainInstanceName
                $expectedAlter = "Altering server role $role2Name"
                $expectedRename = "Renaming server role $role2Name to dbatoolscli_neverapplied_$random"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAlter`" on target `"$expectedTarget`""))
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedRename`" on target `"$expectedTarget`""))
            } finally {
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and NEITHER side effect happened.
            $unchanged = Get-DbaServerRole -SqlInstance $InstanceSingle -ServerRole $role2Name
            $unchanged.Name | Should -Be $role2Name
            $unchanged.Owner | Should -Not -Be $ownerLoginName
        }
    }

    Context "Command behavior" {
        It "Changes the owner via -SqlInstance and re-emits the decorated object" {
            $splatOwner = @{
                SqlInstance     = $InstanceSingle
                ServerRole      = $role2Name
                Owner           = $ownerLoginName
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaServerRole @splatOwner
            $result.Owner | Should -Be $ownerLoginName
            # Decoration parity with Get-DbaServerRole so Get -> Set -> Get composes, including the
            # Login note-property from EnumMemberNames().
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.Role | Should -Be $role2Name
            $result.PSObject.Properties.Name | Should -Contain "Login"
        }

        It "Renames the role as a second round-trip" {
            $splatRename = @{
                SqlInstance     = $InstanceSingle
                ServerRole      = $renameSourceName
                NewName         = $renameTargetName
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaServerRole @splatRename
            $result.Name | Should -Be $renameTargetName
            Get-DbaServerRole -SqlInstance $InstanceSingle -ServerRole $renameSourceName | Should -BeNullOrEmpty
        }

        It "Applies the owner change AND the rename in one call" {
            $bothSourceName = "dbatoolscli_sboth_$random"
            $bothTargetName = "dbatoolscli_sbothrenamed_$random"
            New-DbaServerRole -SqlInstance $InstanceSingle -ServerRole $bothSourceName -EnableException

            $splatBoth = @{
                SqlInstance     = $InstanceSingle
                ServerRole      = $bothSourceName
                Owner           = $ownerLoginName
                NewName         = $bothTargetName
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaServerRole @splatBoth
            $result.Name | Should -Be $bothTargetName
            $result.Owner | Should -Be $ownerLoginName

            Remove-DbaServerRole -SqlInstance $InstanceSingle -ServerRole $bothTargetName -Confirm:$false -EnableException
        }

        It "Processes multiple piped roles and resolves each record's own parent (N in, N out)" {
            # Multi-record piped leg. Two distinct roles piped in must both come back altered, each
            # resolving its own parent server.
            $splatGetPair = @{
                SqlInstance = $InstanceSingle
                ServerRole  = $role1Name, $role2Name
            }
            $results = Get-DbaServerRole @splatGetPair | Set-DbaServerRole -Owner $ownerLoginName -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            ($results.Owner | Sort-Object -Unique) | Should -Be $ownerLoginName
            ($results.Name | Sort-Object) | Should -Be @($role1Name, $role2Name | Sort-Object)

            # Read back independently.
            (Get-DbaServerRole -SqlInstance $InstanceSingle -ServerRole $role1Name).Owner | Should -Be $ownerLoginName
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                ServerRole      = $role1Name
                Owner           = $ownerLoginName
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaServerRole @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Rejects an empty -Owner up front" {
            # SMO throws FailedOperationException on a dirty empty Owner; the command must catch it.
            $splatEmpty = @{
                SqlInstance     = $InstanceSingle
                ServerRole      = $role2Name
                Owner           = ""
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnEmpty"
            }
            $results = Set-DbaServerRole @splatEmpty
            $warnEmpty | Should -BeLike "*Owner cannot be an empty string*"
            $results | Should -BeNullOrEmpty
        }

        It "Refuses to alter a fixed role and continues" {
            # SMO does not block altering a fixed role; the command must catch IsFixedRole itself.
            $splatFixed = @{
                SqlInstance     = $InstanceSingle
                ServerRole      = "sysadmin", $role2Name
                Owner           = $ownerLoginName
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnFixed"
            }
            $results = Set-DbaServerRole @splatFixed
            $warnFixed | Should -BeLike "*fixed role*"
            ($results | Measure-Object).Count | Should -Be 1
        }

        It "Warns and continues on an unknown role without -EnableException" {
            $splatWarn = @{
                SqlInstance     = $InstanceSingle
                ServerRole      = "dbatoolscli_invalidRole_$random", $role2Name
                Owner           = $ownerLoginName
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            $results = Set-DbaServerRole @splatWarn
            $warn | Should -Not -BeNullOrEmpty
            ($results | Measure-Object).Count | Should -Be 1
        }

        It "Throws a terminating error with -EnableException" {
            $splatThrow = @{
                SqlInstance     = $InstanceSingle
                ServerRole      = "dbatoolscli_invalidRole_$random"
                Owner           = $ownerLoginName
                Confirm         = $false
                EnableException = $true
            }
            { Set-DbaServerRole @splatThrow } | Should -Throw
        }
    }
}
