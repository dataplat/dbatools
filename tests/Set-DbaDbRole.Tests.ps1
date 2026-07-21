#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbRole",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaDbRole.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Role",
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
        $ownerLoginName = "dbatoolscli_ownerlogin_$random"
        $db1Name = "dbatoolscli_db1_$random"
        $db2Name = "dbatoolscli_db2_$random"
        $owner1Name = "dbatoolscli_owner1_$random"
        $role1Name = "dbatoolscli_role1_$random"
        $role2Name = "dbatoolscli_role2_$random"
        $renameSourceName = "dbatoolscli_rrole_$random"
        $renameTargetName = "dbatoolscli_rrenamed_$random"

        New-DbaLogin -SqlInstance $InstanceSingle -Login $ownerLoginName -SecurePassword $securePassword
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $db1Name, $db2Name

        # A role owner must be a database user. Map one dedicated login as a user named owner1 in
        # each database, then use that user as the role owner.
        New-DbaDbUser -SqlInstance $InstanceSingle -Database $db1Name -Login $ownerLoginName -Username $owner1Name
        New-DbaDbUser -SqlInstance $InstanceSingle -Database $db2Name -Login $ownerLoginName -Username $owner1Name

        # role1 exists in BOTH databases under the same name - the multi-record piped leg consumes
        # it, so each piped record must resolve its OWN parent database.
        New-DbaDbRole -SqlInstance $InstanceSingle -Database $db1Name, $db2Name -Role $role1Name
        New-DbaDbRole -SqlInstance $InstanceSingle -Database $db1Name -Role $role2Name
        New-DbaDbRole -SqlInstance $InstanceSingle -Database $db1Name -Role $renameSourceName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $db1Name, $db2Name -Confirm:$false -ErrorAction SilentlyContinue
        Remove-DbaLogin -SqlInstance $InstanceSingle -Login $ownerLoginName -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits BOTH designed ShouldProcess strings and changes nothing" {
            # This command declares TWO shouldProcessTargets because the alter (owner) and the rename
            # are two separate statements, not one atomic operation. -WhatIf must show both.
            # WhatIf text is HOST-DIRECT: a transcript is the reliable in-Pester capture.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_whatif_$random.txt"
            $splatWhatIf = @{
                SqlInstance = $InstanceSingle
                Database    = $db1Name
                Role        = $role2Name
                Owner       = $owner1Name
                NewName     = "dbatoolscli_neverapplied_$random"
                WhatIf      = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Set-DbaDbRole @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $InstanceSingle.DomainInstanceName
                $expectedAlter = "Altering database role $role2Name in database $db1Name"
                $expectedRename = "Renaming database role $role2Name to dbatoolscli_neverapplied_$random in database $db1Name"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAlter`" on target `"$expectedTarget`""))
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedRename`" on target `"$expectedTarget`""))
            } finally {
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and NEITHER side effect happened.
            $unchanged = Get-DbaDbRole -SqlInstance $InstanceSingle -Database $db1Name -Role $role2Name
            $unchanged.Name | Should -Be $role2Name
            $unchanged.Owner | Should -Not -Be $owner1Name
        }
    }

    Context "Command behavior" {
        It "Changes the owner via -SqlInstance and re-emits the decorated object" {
            $splatOwner = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                Role            = $role2Name
                Owner           = $owner1Name
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDbRole @splatOwner
            $result.Owner | Should -Be $owner1Name
            # Decoration parity with Get-DbaDbRole so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be $db1Name
        }

        It "Renames the role as a second round-trip" {
            # Rename is NOT part of Alter(): ScriptRename (Smo/DatabaseRoleBase.cs:482-492) emits its
            # own statement and is unreachable from ScriptAlter.
            $splatRename = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                Role            = $renameSourceName
                NewName         = $renameTargetName
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDbRole @splatRename
            $result.Name | Should -Be $renameTargetName
            Get-DbaDbRole -SqlInstance $InstanceSingle -Database $db1Name -Role $renameSourceName | Should -BeNullOrEmpty
        }

        It "Applies the owner change AND the rename in one call" {
            $bothSourceName = "dbatoolscli_broth_$random"
            $bothTargetName = "dbatoolscli_brothrenamed_$random"
            New-DbaDbRole -SqlInstance $InstanceSingle -Database $db1Name -Role $bothSourceName -EnableException

            $splatBoth = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                Role            = $bothSourceName
                Owner           = $owner1Name
                NewName         = $bothTargetName
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDbRole @splatBoth
            $result.Name | Should -Be $bothTargetName
            $result.Owner | Should -Be $owner1Name
        }

        It "Processes multiple piped roles and resolves each record's own parent database (N in, N out)" {
            # Mandatory multi-record piped leg. role1 exists in db1 AND db2, so a command that carried
            # the first record's parent database would write both alters into db1 and the db2 role
            # would come back untouched.
            $splatGetPair = @{
                SqlInstance = $InstanceSingle
                Database    = $db1Name, $db2Name
                Role        = $role1Name
            }
            $results = Get-DbaDbRole @splatGetPair | Set-DbaDbRole -Owner $owner1Name -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            ($results.Database | Sort-Object -Unique) | Should -Be @($db1Name, $db2Name | Sort-Object)
            ($results.Owner | Sort-Object -Unique) | Should -Be $owner1Name

            # Read back independently - the emitted object could be right while the server is not.
            (Get-DbaDbRole -SqlInstance $InstanceSingle -Database $db2Name -Role $role1Name).Owner | Should -Be $owner1Name
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Role            = $role1Name
                Owner           = $owner1Name
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaDbRole @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Requires -Role when -SqlInstance is supplied" {
            $splatNoRole = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                Owner           = $owner1Name
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNoRole"
            }
            $results = Set-DbaDbRole @splatNoRole
            $warnNoRole | Should -BeLike "*Role is required when SqlInstance is specified*"
            $results | Should -BeNullOrEmpty
        }

        It "Refuses to alter a fixed role and continues" {
            # SMO does not block altering a fixed role; the command must catch IsFixedRole itself.
            $splatFixed = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                Role            = "db_datareader", $role2Name
                Owner           = $owner1Name
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnFixed"
            }
            $results = Set-DbaDbRole @splatFixed
            $warnFixed | Should -BeLike "*fixed role*"
            ($results | Measure-Object).Count | Should -Be 1
        }

        It "Warns and continues on an unknown role without -EnableException" {
            $splatWarn = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                Role            = "dbatoolscli_invalidRole_$random", $role2Name
                Owner           = $owner1Name
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            $results = Set-DbaDbRole @splatWarn
            $warn | Should -Not -BeNullOrEmpty
            ($results | Measure-Object).Count | Should -Be 1
        }

        It "Throws a terminating error with -EnableException" {
            $splatThrow = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                Role            = "dbatoolscli_invalidRole_$random"
                Owner           = $owner1Name
                Confirm         = $false
                EnableException = $true
            }
            { Set-DbaDbRole @splatThrow } | Should -Throw
        }
    }
}
