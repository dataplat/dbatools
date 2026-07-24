#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaLoginInGroup",
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
                "Login",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

<#
Integration test should appear below and are custom to the command you are writing.
Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: this suite pins the command's real behavior against a domain-joined
    # instance carrying at least one Windows AD group login, which is what the command exists to
    # expand. The expected expansion is built from an INDEPENDENT Active Directory read
    # (System.DirectoryServices.AccountManagement, the same API the command uses but driven
    # directly here rather than through the command), so the assertions compare the command's
    # output against directory truth rather than against itself. Selecting WHICH logins are in
    # scope necessarily repeats the command's documented exclusions - BUILTIN\Administrators,
    # NT SERVICE\*, and the host's own local groups - because those exclusions are part of the
    # contract being characterized. The oracle is deliberately FLAT (one level of membership); a
    # guard leg asserts the fixture group holds no nested groups, so a nested-group fixture fails
    # loudly instead of silently under-counting. Recursive expansion of nested groups is
    # therefore NOT covered here and remains unverified.
    BeforeAll {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException

        # Same selection the command documents: Windows groups only, minus the built-in
        # administrators group, minus service SIDs, minus the host's own local groups.
        $groupLogins = @($server.Logins | Where-Object {
                $PSItem.LoginType -eq "WindowsGroup" -and
                $PSItem.Name -ne "BUILTIN\Administrators" -and
                $PSItem.Name -notlike "*NT SERVICE*" -and
                $PSItem.Name -notlike "$($server.ComputerName)\*"
            })

        # Independent directory read: DOMAIN\sam -> the group login it was reached through, plus
        # the display name, and a separate tally of any nested groups encountered.
        $expectedMemberOf = @{}
        $expectedDisplayName = @{}
        $nestedGroupCount = 0
        foreach ($groupLogin in $groupLogins) {
            $domainName = $groupLogin.Name.Split("\")[0]
            $principalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext("Domain", $domainName)
            $adGroup = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($principalContext, $groupLogin.Name)
            foreach ($member in $adGroup.Members) {
                if ($member.StructuralObjectClass -eq "group") {
                    $nestedGroupCount++
                    continue
                }
                $qualifiedName = $member.Context.Name + "\" + $member.SamAccountName
                $expectedMemberOf[$qualifiedName] = $groupLogin.Name
                $expectedDisplayName[$qualifiedName] = $member.DisplayName
            }
        }
        $expectedLogins = @($expectedMemberOf.Keys | Sort-Object)
    }

    Context "Expanding the group logins on a live instance" {
        It "Has a non-empty directory fixture with no nested groups, so the flat oracle is valid" {
            $groupLogins.Count | Should -BeGreaterThan 0
            $expectedLogins.Count | Should -BeGreaterThan 0
            $nestedGroupCount | Should -Be 0
        }

        It "Returns exactly the individual users the directory reports for those group logins" {
            $result = @(Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle)
            $actualLogins = @($result.Login | Sort-Object)
            $actualLogins | Should -Be $expectedLogins
        }

        It "Attributes every user to the group login it was reached through" {
            $result = @(Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle)
            foreach ($row in $result) {
                $row.MemberOf | Should -Be $expectedMemberOf[$row.Login]
                $row.ParentADGroupLogin | Should -Be $expectedMemberOf[$row.Login]
                $row.DisplayName | Should -Be $expectedDisplayName[$row.Login]
                $row.SqlInstance | Should -Be $server.Name
                $row.ComputerName | Should -Be $server.ComputerName
                $row.InstanceName | Should -Be $server.ServiceName
            }
        }

        It "Displays the five documented properties by default while keeping the rest addressable" {
            $result = @(Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle)
            $defaultProperties = @($result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
            $defaultProperties | Should -Be @("SqlInstance", "Login", "DisplayName", "MemberOf", "ParentADGroupLogin")
        }
    }

    Context "Filtering with -Login" {
        It "Narrows the expansion to the requested user" {
            $targetLogin = $expectedLogins[0]
            $result = @(Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle -Login $targetLogin)
            $result.Count | Should -Be 1
            $result[0].Login | Should -Be $targetLogin
        }

        It "Emits nothing when no group member matches the requested user" {
            $result = @(Find-DbaLoginInGroup -SqlInstance $TestConfig.InstanceSingle -Login "LAB\dbatoolsci-nosuchuser-$(Get-Random)")
            $result.Count | Should -Be 0
        }
    }

    Context "Unreachable instance" {
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

        It "Warns and returns nothing without throwing" {
            # Called directly rather than inside a Should -Not -Throw scriptblock: -WarningVariable
            # publishes into the scope the call runs in, so a wrapping scriptblock captures the
            # warning somewhere the assertions cannot read. A terminating error would fail this It
            # on its own, which is the same characterization the wrapper was there to make.
            $splatUnreachable = @{
                SqlInstance     = $TestConfig.InstanceUnreachable
                WarningVariable = "connectWarning"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $result = @(Find-DbaLoginInGroup @splatUnreachable)
            $result.Count | Should -Be 0
            $connectWarning | Should -Not -BeNullOrEmpty
        }
    }
}
