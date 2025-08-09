#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaCredential",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig
. "$PSScriptRoot\..\private\functions\Invoke-Command2.ps1"


Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters      = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $logins    = "thor", "thorsmomma"
        $plaintext = "BigOlPassword!"
        $password  = ConvertTo-SecureString $plaintext -AsPlainText -Force

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

        $splatMommaCred = @{
            SqlInstance = $TestConfig.instance2
            Identity    = "thorsmomma"
            Password    = $password
        }
        $null = New-DbaCredential @splatMommaCred
    }

    AfterAll {
        $splatGetCred = @{
            SqlInstance   = $TestConfig.instance2
            Identity      = "thor", "thorsmomma"
            ErrorAction   = "Stop"
            WarningAction = "SilentlyContinue"
        }
        try {
            (Get-DbaCredential @splatGetCred).Drop()
        } catch { }

        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $TestConfig.instance2
        }
    }

    Context "Get credentials" {
        It "Should get just one credential with the proper properties when using Identity" {
            $results = Get-DbaCredential -SqlInstance $TestConfig.instance2 -Identity thorsmomma
            $results.Name | Should -Be "thorsmomma"
            $results.Identity | Should -Be "thorsmomma"
        }

        It "Should get just one credential with the proper properties when using Name" {
            $results = Get-DbaCredential -SqlInstance $TestConfig.instance2 -Name thorsmomma
            $results.Name | Should -Be "thorsmomma"
            $results.Identity | Should -Be "thorsmomma"
        }

        It "gets more than one credential" {
            $results = Get-DbaCredential -SqlInstance $TestConfig.instance2 -Identity thor, thorsmomma
            $results.Status.Count | Should -BeGreaterThan 1
        }
    }
}