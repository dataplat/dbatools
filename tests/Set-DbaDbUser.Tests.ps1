#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbUser",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaDbUser.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "User",
                "DefaultSchema",
                "Login",
                "NewName",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should carry the Username alias on -User" {
            (Get-Command $CommandName).Parameters["User"].Aliases | Should -Contain "Username"
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
        # A login maps to at most ONE user per database, so each db1 user needs its own login.
        $login1Name = "dbatoolscli_login1_$random"
        $login2Name = "dbatoolscli_login2_$random"
        $login3Name = "dbatoolscli_login3_$random"
        $login4Name = "dbatoolscli_login4_$random"
        $login5Name = "dbatoolscli_login5_$random"
        $db1Name = "dbatoolscli_db1_$random"
        $db2Name = "dbatoolscli_db2_$random"
        $schema1Name = "dbatoolscli_schema1_$random"
        $schema2Name = "dbatoolscli_schema2_$random"
        $user1Name = "dbatoolscli_user1_$random"
        $user2Name = "dbatoolscli_user2_$random"
        $renameSourceName = "dbatoolscli_rename_$random"
        $renameTargetName = "dbatoolscli_renamed_$random"

        New-DbaLogin -SqlInstance $InstanceSingle -Login $login1Name, $login2Name, $login3Name, $login4Name, $login5Name -SecurePassword $securePassword
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $db1Name, $db2Name

        New-DbaDbSchema -SqlInstance $InstanceSingle -Database $db1Name -Schema $schema1Name, $schema2Name
        New-DbaDbSchema -SqlInstance $InstanceSingle -Database $db2Name -Schema $schema1Name

        # user1 exists in BOTH databases under the same name - this is what the multi-record piped
        # test consumes, so each piped record must resolve its OWN parent database. login1 maps to
        # user1 in db1 and db2 (different databases, so the same login is fine).
        New-DbaDbUser -SqlInstance $InstanceSingle -Database $db1Name, $db2Name -Login $login1Name -Username $user1Name
        New-DbaDbUser -SqlInstance $InstanceSingle -Database $db1Name -Login $login2Name -Username $user2Name
        New-DbaDbUser -SqlInstance $InstanceSingle -Database $db1Name -Login $login3Name -Username $renameSourceName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $db1Name, $db2Name -Confirm:$false -ErrorAction SilentlyContinue
        Remove-DbaLogin -SqlInstance $InstanceSingle -Login $login1Name, $login2Name, $login3Name, $login4Name, $login5Name -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits BOTH designed ShouldProcess strings and changes nothing" {
            # This command declares TWO shouldProcessTargets because the alter and the rename are two
            # separate statements against the server, not one atomic operation. -WhatIf must show
            # both, or a user cannot see that a failed rename leaves a completed alter behind.
            # WhatIf text is HOST-DIRECT: *>&1 / 6>&1 capture nothing in-process, so a transcript is
            # the reliable in-Pester capture.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_whatif_$random.txt"
            $splatWhatIf = @{
                SqlInstance   = $InstanceSingle
                Database      = $db1Name
                User          = $user2Name
                DefaultSchema = $schema1Name
                NewName       = "dbatoolscli_neverapplied_$random"
                WhatIf        = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Set-DbaDbUser @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $InstanceSingle.DomainInstanceName
                $expectedAlter = "Altering database user $user2Name in database $db1Name"
                $expectedRename = "Renaming database user $user2Name to dbatoolscli_neverapplied_$random in database $db1Name"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAlter`" on target `"$expectedTarget`""))
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedRename`" on target `"$expectedTarget`""))
            } finally {
                # Stop-Transcript writes to the error stream even under -ErrorAction
                # SilentlyContinue when the host is no longer transcribing, and Pester counts that
                # as a failure - swallow it in a catch instead.
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and NEITHER side effect happened.
            $unchanged = Get-DbaDbUser -SqlInstance $InstanceSingle -Database $db1Name -User $user2Name
            $unchanged.Name | Should -Be $user2Name
            $unchanged.DefaultSchema | Should -Not -Be $schema1Name
        }
    }

    Context "Command behavior" {
        It "Alters the default schema via -SqlInstance and re-emits the decorated object" {
            $splatSchema = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                User            = $user2Name
                DefaultSchema   = $schema1Name
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDbUser @splatSchema
            $result.DefaultSchema | Should -Be $schema1Name
            # Decoration parity with Get-DbaDbUser so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be $db1Name
        }

        It "Remaps the login and leaves the default schema alone when -DefaultSchema is omitted" {
            # THE regression this command is most likely to have. ScriptAlter dirty-gates
            # DEFAULT_SCHEMA and LOGIN independently (Smo/UserBase.cs:1171, :1190), so an unbound
            # parameter must emit no clause at all - never a clause carrying a stale or empty value.
            # login5 is free in db1 (a login maps to one user per database), so user2 can remap to it.
            $splatLogin = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                User            = $user2Name
                Login           = $login5Name
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDbUser @splatLogin
            $result.Login | Should -Be $login5Name
            $result.DefaultSchema | Should -Be $schema1Name
        }

        It "Renames the user as a second round-trip" {
            # Rename is NOT part of Alter(): ScriptRename (Smo/UserBase.cs:1368-1379) emits its own
            # statement and is unreachable from ScriptAlter, so setting .Name and calling Alter()
            # would silently do nothing.
            $splatRename = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                User            = $renameSourceName
                NewName         = $renameTargetName
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDbUser @splatRename
            $result.Name | Should -Be $renameTargetName
            Get-DbaDbUser -SqlInstance $InstanceSingle -Database $db1Name -User $renameSourceName | Should -BeNullOrEmpty
        }

        It "Applies the alter AND the rename in one call, in that order" {
            $bothSourceName = "dbatoolscli_both_$random"
            $bothTargetName = "dbatoolscli_bothrenamed_$random"
            New-DbaDbUser -SqlInstance $InstanceSingle -Database $db1Name -Login $login4Name -Username $bothSourceName -EnableException

            $splatBoth = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                User            = $bothSourceName
                DefaultSchema   = $schema2Name
                NewName         = $bothTargetName
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDbUser @splatBoth
            $result.Name | Should -Be $bothTargetName
            $result.DefaultSchema | Should -Be $schema2Name
        }

        It "Processes multiple piped users and resolves each record's own parent database (N in, N out)" {
            # Mandatory multi-record piped leg. user1 exists in db1 AND db2, so a command that
            # carried the first record's parent database would write both alters into db1 and the
            # db2 user would come back untouched.
            $splatGetPair = @{
                SqlInstance = $InstanceSingle
                Database    = $db1Name, $db2Name
                User        = $user1Name
            }
            $results = Get-DbaDbUser @splatGetPair | Set-DbaDbUser -DefaultSchema $schema1Name -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            ($results.Database | Sort-Object -Unique) | Should -Be @($db1Name, $db2Name | Sort-Object)
            ($results.DefaultSchema | Sort-Object -Unique) | Should -Be $schema1Name

            # Read back independently - the emitted object could be right while the server is not.
            (Get-DbaDbUser -SqlInstance $InstanceSingle -Database $db2Name -User $user1Name).DefaultSchema | Should -Be $schema1Name
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                User            = $user1Name
                DefaultSchema   = $schema1Name
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaDbUser @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Requires -User when -SqlInstance is supplied" {
            # A Set- that fans across every user in every database because a filter was omitted is
            # not a defensible default.
            $splatNoUser = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                DefaultSchema   = $schema1Name
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNoUser"
            }
            $results = Set-DbaDbUser @splatNoUser
            $warnNoUser | Should -BeLike "*User is required when SqlInstance is specified*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues on an unknown user without -EnableException" {
            $splatWarn = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                User            = "dbatoolscli_invalidUser_$random", $user2Name
                DefaultSchema   = $schema2Name
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            $results = Set-DbaDbUser @splatWarn
            $warn | Should -Not -BeNullOrEmpty
            ($results | Measure-Object).Count | Should -Be 1
        }

        It "Throws a terminating error with -EnableException" {
            $splatThrow = @{
                SqlInstance     = $InstanceSingle
                Database        = $db1Name
                User            = "dbatoolscli_invalidUser_$random"
                DefaultSchema   = $schema2Name
                Confirm         = $false
                EnableException = $true
            }
            { Set-DbaDbUser @splatThrow } | Should -Throw
        }
    }
}
