#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaCredential",
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
                "Name",
                "Identity",
                "SecurePassword",
                "MappedClassType",
                "ProviderName",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $logins = "thor", "thorsmomma"
        $plaintext = "BigOlPassword!"
        $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

        # Add user
        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args[0] $args[1] /add *>&1 } -ArgumentList $login, $plaintext -ComputerName $TestConfig.InstanceSingle
        }
    }

    AfterAll {
        try {
            (Get-DbaCredential -SqlInstance $TestConfig.InstanceSingle -Identity thor, thorsmomma -ErrorAction Stop -WarningAction SilentlyContinue).Drop()
            (Get-DbaCredential -SqlInstance $TestConfig.InstanceSingle -Name "https://mystorageaccount.blob.core.windows.net/mycontainer" -ErrorAction Stop -WarningAction SilentlyContinue).Drop()
        } catch { }

        foreach ($login in $logins) {
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $TestConfig.InstanceSingle
        }
    }

    Context "Create a new credential" {
        It "Should create new credentials with the proper properties" {
            $results = New-DbaCredential -SqlInstance $TestConfig.InstanceSingle -Name thorcred -Identity thor -Password $password
            $results.Name | Should -Be "thorcred"
            $results.Identity | Should -Be "thor"

            $results = New-DbaCredential -SqlInstance $TestConfig.InstanceSingle -Identity thorsmomma -Password $password
            $results | Should -Not -Be $null
        }

        It "Gets the newly created credential" {
            $results = Get-DbaCredential -SqlInstance $TestConfig.InstanceSingle -Identity thorsmomma
            $results.Name | Should -Be "thorsmomma"
            $results.Identity | Should -Be "thorsmomma"
        }
    }

    Context "Create a new credential without password" {
        It "Should create new credentials with the proper properties but without password" {
            $splatCredential = @{
                SqlInstance = $TestConfig.InstanceSingle
                Name        = "https://mystorageaccount.blob.core.windows.net/mycontainer"
                Identity    = "Managed Identity"
            }
            $results = New-DbaCredential @splatCredential
            $results.Name | Should -Be "https://mystorageaccount.blob.core.windows.net/mycontainer"
            $results.Identity | Should -Be "Managed Identity"
        }

        It "Gets the newly created credential that doesn't have password" {
            $results = Get-DbaCredential -SqlInstance $TestConfig.InstanceSingle -Identity "Managed Identity"
            $results.Name | Should -Be "https://mystorageaccount.blob.core.windows.net/mycontainer"
            $results.Identity | Should -Be "Managed Identity"
        }
    }
}