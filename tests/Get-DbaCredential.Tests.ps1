#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaCredential",
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
                "Credential",
                "ExcludeCredential",
                "Identity",
                "ExcludeIdentity",
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

        $logins = "thor", "thorsmomma", "wildcardcred"
        $plaintext = "BigOlPassword!"
        $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

        # Add user
        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $login, $plaintext -ComputerName $TestConfig.instance2
        }

        $splatThorCred = @{
            SqlInstance = $TestConfig.instance2
            Name        = "thorcred"
            Identity    = "thor"
            Password    = $password
        }
        $null = New-DbaCredential @splatThorCred

        $splatThorsmormmaCred = @{
            SqlInstance = $TestConfig.instance2
            Identity    = "thorsmomma"
            Password    = $password
        }
        $null = New-DbaCredential @splatThorsmormmaCred

        $splatWildcardCred = @{
            SqlInstance = $TestConfig.instance2
            Identity    = "wildcardcred"
            Password    = $password
        }
        $null = New-DbaCredential @splatWildcardCred

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        try {
            $splatGetCred = @{
                SqlInstance   = $TestConfig.instance2
                Identity      = "thor", "thorsmomma", "wildcardcred"
                ErrorAction   = "Stop"
                WarningAction = "SilentlyContinue"
            }
            (Get-DbaCredential @splatGetCred).Drop()
        } catch { }

        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $TestConfig.instance2
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Get credentials" {
        It "Should get just one credential with the proper properties when using Identity" {
            $results = Get-DbaCredential -SqlInstance $TestConfig.instance2 -Identity "thorsmomma"
            $results.Name | Should -Be "thorsmomma"
            $results.Identity | Should -Be "thorsmomma"
        }
        It "Should get just one credential with the proper properties when using Name" {
            $results = Get-DbaCredential -SqlInstance $TestConfig.instance2 -Name "thorsmomma"
            $results.Name | Should -Be "thorsmomma"
            $results.Identity | Should -Be "thorsmomma"
        }
        It "Should get just one credential when using a wildcard in Identity" {
            $results = Get-DbaCredential -SqlInstance $TestConfig.instance2 -Identity "card"
            $results.Name | Should -Be "wildcardcred"
            $results.Identity | Should -Be "wildcardcred"
        }
        It "Should get two credentials when excluding the wildcardcred in ExcludeIdentity" {
            $results = Get-DbaCredential -SqlInstance $TestConfig.instance2 -ExcludeIdentity "card"
            $results.Name | Should -Be @("thorcred", "thorsmomma")
            $results.Identity | Should -Be @("thor", "thorsmomma")
        }
        It "gets more than one credential" {
            $splatMultipleCreds = @{
                SqlInstance = $TestConfig.instance2
                Identity    = "thor", "thorsmomma", "wildcardcred"
            }
            $results = Get-DbaCredential @splatMultipleCreds
            $results.Count | Should -BeGreaterThan 2
        }
    }
}