#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaPrivilege",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "Type",
                "User",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

InModuleScope dbatools {
    Describe "Remove-DbaPrivilege service account discovery" -Tag UnitTests {
        BeforeEach {
            $script:removedAccounts = $null

            Mock Test-ElevationRequirement { $true }
            Mock Test-PSRemoting { $true }
            Mock Get-DbaService {
                [PSCustomObject]@{ ServiceName = "MSSQLSERVER"; StartName = "CONTOSO\SqlSvc" }
                [PSCustomObject]@{ ServiceName = "MSSQL`$SYSTEMINSTANCE"; StartName = "LocalSystem" }
                [PSCustomObject]@{ ServiceName = "MSSQL`$NETWORKINSTANCE"; StartName = "NT AUTHORITY\NetworkService" }
                [PSCustomObject]@{ ServiceName = "MSSQL`$VIRTUALINSTANCE"; StartName = "NT Service\MSSQL`$VIRTUALINSTANCE" }
            }
            Mock Invoke-Command2 {
                param(
                    $ComputerName,
                    $Credential,
                    $ScriptBlock,
                    $ArgumentList
                )
                $script:removedAccounts = $ArgumentList[0]
            }
        }

        It "takes the per-service SIDs and the service accounts, but never the shared built-in accounts" {
            # The built-in accounts share their rights with every other service that runs under them,
            # so revoking from them would break services that have nothing to do with SQL Server.
            $null = Remove-DbaPrivilege -ComputerName $env:COMPUTERNAME -Type IFI -Confirm:$false -WarningAction SilentlyContinue

            $expectedAccounts = @(
                "CONTOSO\SqlSvc",
                "NT SERVICE\MSSQL`$NETWORKINSTANCE",
                "NT SERVICE\MSSQL`$SYSTEMINSTANCE",
                "NT SERVICE\MSSQL`$VIRTUALINSTANCE",
                "NT SERVICE\MSSQLSERVER"
            )
            Compare-Object -ReferenceObject $expectedAccounts -DifferenceObject @($script:removedAccounts) | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Returns the entries of one right from the local security policy, the way secedit exports them:
        # *SID for most accounts, the bare name for local accounts.
        function Get-TestRightEntry {
            param ([string]$Privilege)
            $exportFile = "$([System.IO.Path]::GetTempPath())dbatoolsci_rights_$(Get-Random).cfg"
            try {
                $null = secedit /export /cfg $exportFile /areas USER_RIGHTS
                $line = Get-Content -Path $exportFile | Where-Object { $PSItem -match "^$Privilege\s*=" }
                if ($line) {
                    $line.Split("=", 2)[1].Split(",") | ForEach-Object { $PSItem.Trim() } | Where-Object { $PSItem }
                }
            } finally {
                Remove-Item -Path $exportFile -ErrorAction SilentlyContinue
            }
        }

        $testUsers = @()
        $testSids = @()
        foreach ($i in 1..2) {
            $testUserName = "dbatoolsci_priv$i$(Get-Random -Maximum 9999)"
            $splatTestUser = @{
                Name     = $testUserName
                Password = (ConvertTo-SecureString -String "dbatools.IO!$(Get-Random)" -AsPlainText -Force)
            }
            $null = New-LocalUser @splatTestUser
            $testUsers += $testUserName
            $testSids += ([System.Security.Principal.NTAccount]"$env:COMPUTERNAME\$testUserName").Translate([System.Security.Principal.SecurityIdentifier]).Value
        }

        # True when the right lists the account, by its bare name or by its SID.
        function Test-TestRightHolder {
            param (
                [string]$Privilege,
                [string]$UserName,
                [string]$Sid
            )
            @(Get-TestRightEntry -Privilege $Privilege | Where-Object { $PSItem -eq $UserName -or $PSItem -eq "*$Sid" }).Count -gt 0
        }
        $testAccount = "$env:COMPUTERNAME\$($testUsers[0])"
        $testSid = $testSids[0]

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # Revoke whatever a failed test left behind, by SID, so that it also works after the user is gone.
        foreach ($sid in $testSids) {
            $splatCleanup = @{
                Type          = "IFI", "LPIM", "BatchLogon", "SecAudit", "ServiceLogon", "CreateGlobalObjects"
                User          = $sid
                WarningAction = "SilentlyContinue"
            }
            $null = Remove-DbaPrivilege @splatCleanup
        }
        foreach ($testUserName in $testUsers) {
            Remove-LocalUser -Name $testUserName -ErrorAction SilentlyContinue
        }
    }

    Context "Removing privileges from an account" {
        It "Revokes the privileges and keeps the other holders" {
            $null = Set-DbaPrivilege -Type LPIM, CreateGlobalObjects -User $testAccount
            $holdersBefore = @(Get-TestRightEntry -Privilege SeCreateGlobalPrivilege | Where-Object { $PSItem -notin $testUsers[0], "*$testSid" })

            $result = Remove-DbaPrivilege -Type LPIM, CreateGlobalObjects -User $testAccount

            $WarnVar | Should -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result.Type | Should -Be "LPIM", "CreateGlobalObjects"
            $result.Privilege | Should -Be "SeLockMemoryPrivilege", "SeCreateGlobalPrivilege"
            $result.Status | Should -Be "Removed", "Removed"
            $result[0].ComputerName | Should -Be $env:COMPUTERNAME
            $result[0].User | Should -Be $testAccount

            # secedit exports a local account by its bare name, so both forms are checked.
            Test-TestRightHolder -Privilege SeLockMemoryPrivilege -UserName $testUsers[0] -Sid $testSid | Should -BeFalse
            Test-TestRightHolder -Privilege SeCreateGlobalPrivilege -UserName $testUsers[0] -Sid $testSid | Should -BeFalse
            # Administrators, SERVICE and the other default holders must survive the edit of the line.
            @(Get-TestRightEntry -Privilege SeCreateGlobalPrivilege) | Should -Be $holdersBefore
        }

        It "Warns and returns nothing when the account does not hold the privilege" {
            $result = Remove-DbaPrivilege -Type BatchLogon -User $testAccount -WarningAction SilentlyContinue

            $result | Should -BeNullOrEmpty
            $WarnVar | Should -BeLike "*did not hold BatchLogon (SeBatchLogonRight)*"
        }

        It "Changes nothing with -WhatIf" {
            $null = Set-DbaPrivilege -Type BatchLogon -User $testAccount

            $result = Remove-DbaPrivilege -Type BatchLogon -User $testAccount -WhatIf

            $result | Should -BeNullOrEmpty
            Test-TestRightHolder -Privilege SeBatchLogonRight -UserName $testUsers[0] -Sid $testSid | Should -BeTrue

            $null = Remove-DbaPrivilege -Type BatchLogon -User $testAccount
            Test-TestRightHolder -Privilege SeBatchLogonRight -UserName $testUsers[0] -Sid $testSid | Should -BeFalse
        }
    }

    Context "Removing privileges from an account that no longer exists" {
        It "Revokes the privilege by the SID" {
            $orphanAccount = "$env:COMPUTERNAME\$($testUsers[1])"
            $null = Set-DbaPrivilege -Type BatchLogon -User $orphanAccount
            Remove-LocalUser -Name $testUsers[1]
            # Without the account, secedit can only write the SID.
            @(Get-TestRightEntry -Privilege SeBatchLogonRight) | Should -Contain "*$($testSids[1])"

            $result = Remove-DbaPrivilege -Type BatchLogon -User $testSids[1]

            $result.User | Should -Be $testSids[1]
            $result.Status | Should -Be "Removed"
            @(Get-TestRightEntry -Privilege SeBatchLogonRight) | Should -Not -Contain "*$($testSids[1])"
        }
    }
}
