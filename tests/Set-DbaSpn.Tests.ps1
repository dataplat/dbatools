#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaSpn",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SPN",
                "ServiceAccount",
                "Credential",
                "NoDelegation",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

# AD writes need a domain; the AppVeyor host is a standalone workgroup box, so these run on the
# lab (and anywhere else domain-joined) only. The SPNs used are unique dbatoolsci fabrications on
# the local machine's own computer account - no real service references them, and AfterAll strips
# them directly from AD so a failed test never leaves residue.
Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    BeforeAll {
        $testAccount     = "$env:USERDOMAIN\$env:COMPUTERNAME`$"
        $testSpnBase     = "MSSQLSvc/dbatoolsci-w5039-$(Get-Random).lab.local"
        $testSpn         = "$testSpnBase`:1433"
        $testSpnNoDeleg  = "$testSpnBase`:2433"
    }

    AfterAll {
        # Remove both SPNs and any delegation entries straight from AD, position-independently,
        # regardless of what the tests managed to do.
        # Bind the verification read to the DOMAIN (the same DC-locator binding the command's
        # Get-DbaADObject write path uses): the lab runs TWO DCs, and a serverless bind can hit
        # the OTHER one before replication converges - an immediate read there sees stale state.
        $searcher = [ADSISearcher]"(&(objectClass=computer)(name=$env:COMPUTERNAME))"
        $searcher.SearchRoot = [ADSI]"LDAP://$env:USERDOMAIN"
        $adEntry = $searcher.FindOne().GetDirectoryEntry()
        foreach ($prop in @("servicePrincipalName", "msDS-AllowedToDelegateTo")) {
            foreach ($value in @($testSpn, $testSpnNoDeleg)) {
                if ($adEntry.Properties[$prop] -contains $value) {
                    $null = $adEntry.Properties[$prop].Remove($value)
                }
            }
        }
        $adEntry.CommitChanges()
    }

    Context "Registering an SPN on the local computer account" {
        It "Adds the SPN and the delegation entry" {
            $results = @(Set-DbaSpn -SPN $testSpn -ServiceAccount $testAccount -Confirm:$false 3>$null)
            $results.Count | Should -Be 2
            $results[0].Name | Should -Be $testSpn
            $results[0].ServiceAccount | Should -Be $testAccount
            $results[0].Property | Should -Be "servicePrincipalName"
            $results[0].IsSet | Should -BeTrue
            $results[0].Notes | Should -Be "Successfully added SPN"
            $results[1].Name | Should -Be $testSpn
            $results[1].Property | Should -Be "msDS-AllowedToDelegateTo"
            $results[1].IsSet | Should -BeTrue
            $results[1].Notes | Should -Be "Successfully added constrained delegation"
        }

        It "Shows the registered SPN through Get-DbaSpn" {
            $registered = Get-DbaSpn -AccountName $testAccount 3>$null
            $registered.SPN | Should -Contain $testSpn
        }

        It "Is idempotent - a duplicate add still reports success and AD keeps a single value" {
            # ADSI silently dedupes an Add of an already-present value (empirically verified on
            # the lab DC), so a duplicate add is NOT the failure path - it reports success again.
            $splatDuplicate = @{
                SPN             = $testSpn
                ServiceAccount  = $testAccount
                Confirm         = $false
                WarningVariable = "warnDuplicate"
            }
            $results = @(Set-DbaSpn @splatDuplicate 3>$null)
            $warnDuplicate | Should -BeNullOrEmpty
            $results.Count | Should -Be 2
            $results[0].IsSet | Should -BeTrue
            $results[0].Notes | Should -Be "Successfully added SPN"

            # Domain-bound read: same DC-locator binding as the command's write path (two-DC lab,
            # serverless binds can hit the other DC before replication converges).
            $searcher = [ADSISearcher]"(&(objectClass=computer)(name=$env:COMPUTERNAME))"
            $searcher.SearchRoot = [ADSI]"LDAP://$env:USERDOMAIN"
            $adEntry = $searcher.FindOne().GetDirectoryEntry()
            @($adEntry.Properties["servicePrincipalName"] | Where-Object { $PSItem -eq $testSpn }).Count | Should -Be 1
        }

        It "Skips delegation when NoDelegation is specified" {
            $splatNoDelegation = @{
                SPN            = $testSpnNoDeleg
                ServiceAccount = $testAccount
                NoDelegation   = $true
                Confirm        = $false
            }
            $results = @(Set-DbaSpn @splatNoDelegation 3>$null)
            $results.Count | Should -Be 1
            $results[0].Property | Should -Be "servicePrincipalName"
            $results[0].IsSet | Should -BeTrue
            $results[0].Notes | Should -Be "Successfully added SPN"
        }
    }
}
