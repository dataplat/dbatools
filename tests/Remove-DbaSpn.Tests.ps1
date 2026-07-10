#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaSpn",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

# AD writes need a domain; the AppVeyor host is a standalone workgroup box, so these run on the
# lab (and anywhere else domain-joined) only. BeforeAll registers unique dbatoolsci SPNs on the
# local machine's own computer account via Set-DbaSpn, the tests remove them, and AfterAll strips
# any leftovers directly from AD so a failed test never leaves residue.
Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $testAccount     = "$env:USERDOMAIN\$env:COMPUTERNAME`$"
        $testSpnBase     = "MSSQLSvc/dbatoolsci-w5034-$(Get-Random).lab.local"
        $testSpnDeleg    = "$testSpnBase`:1433"
        $testSpnNoDeleg  = "$testSpnBase`:2433"
        $null = Set-DbaSpn -SPN $testSpnDeleg -ServiceAccount $testAccount -Confirm:$false 3>$null
        $null = Set-DbaSpn -SPN $testSpnNoDeleg -ServiceAccount $testAccount -NoDelegation -Confirm:$false 3>$null

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
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
            foreach ($value in @($testSpnDeleg, $testSpnNoDeleg)) {
                if ($adEntry.Properties[$prop] -contains $value) {
                    $null = $adEntry.Properties[$prop].Remove($value)
                }
            }
        }
        $adEntry.CommitChanges()
    }

    Context "Removing SPNs from the local computer account" {
        It "Removes the SPN and its delegation entry" {
            $results = @(Remove-DbaSpn -SPN $testSpnDeleg -ServiceAccount $testAccount -Confirm:$false 3>$null)
            $results.Count | Should -Be 2
            $results[0].Name | Should -Be $testSpnDeleg
            $results[0].ServiceAccount | Should -Be $testAccount
            $results[0].Property | Should -Be "servicePrincipalName"
            $results[0].IsSet | Should -BeFalse
            $results[0].Notes | Should -Be "Successfully removed SPN"
            $results[1].Property | Should -Be "msDS-AllowedToDelegateTo"
            $results[1].IsSet | Should -BeFalse
            $results[1].Notes | Should -Be "Successfully removed delegation"
        }

        It "Reports not-found when the SPN was already removed" {
            $splatRepeat = @{
                SPN             = $testSpnDeleg
                ServiceAccount  = $testAccount
                Confirm         = $false
                WarningVariable = "warnRepeat"
            }
            $results = @(Remove-DbaSpn @splatRepeat 3>$null)
            $warnRepeat | Should -Match "not found"
            $results.Count | Should -Be 2
            $results[0].Property | Should -Be "servicePrincipalName"
            $results[0].IsSet | Should -BeFalse
            $results[0].Notes | Should -Be "SPN not found"
            $results[1].Property | Should -Be "msDS-AllowedToDelegateTo"
            $results[1].IsSet | Should -BeFalse
            $results[1].Notes | Should -Be "Delegation not found"
        }

        It "Removes an SPN that never had delegation and reports the delegation as not found" {
            $results = @(Remove-DbaSpn -SPN $testSpnNoDeleg -ServiceAccount $testAccount -Confirm:$false 3>$null)
            $results.Count | Should -Be 2
            $results[0].Property | Should -Be "servicePrincipalName"
            $results[0].IsSet | Should -BeFalse
            $results[0].Notes | Should -Be "Successfully removed SPN"
            $results[1].Property | Should -Be "msDS-AllowedToDelegateTo"
            $results[1].IsSet | Should -BeFalse
            $results[1].Notes | Should -Be "Delegation not found"
        }
    }
}
