#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbAzSqlTip",
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
                "AzureDomain",
                "Tenant",
                "LocalFile",
                "Database",
                "ExcludeDatabase",
                "AllUserDatabases",
                "ReturnAllTips",
                "Compat100",
                "StatementTimeout",
                "EnableException",
                "Force"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:($env:azuredbpasswd -ne "failstoooften") {
    Context "Run the tips against Azure database" {
        BeforeAll {
            $securePassword = ConvertTo-SecureString $env:azuredbpasswd -AsPlainText -Force
            $splatCredential = @{
                UserName    = $TestConfig.azuresqldblogin
                Password    = $securePassword
                ErrorAction = "Stop"
            }
            $cred = New-Object System.Management.Automation.PSCredential @splatCredential

            $splatInvokeTips = @{
                SqlInstance     = $TestConfig.azureserver
                Database        = "test"
                SqlCredential   = $cred
                ReturnAllTips   = $true
                EnableException = $true
            }
            $results = Invoke-DbaDbAzSqlTip @splatInvokeTips
        }

        It "Should get some results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have the right ComputerName" {
            $results.ComputerName | Should -Be $TestConfig.azureserver
        }

        It "Database name should be 'test'" {
            $results.Database | Should -Be "test"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $securePassword = ConvertTo-SecureString $env:azuredbpasswd -AsPlainText -Force
            $splatCredential = @{
                UserName    = $TestConfig.azuresqldblogin
                Password    = $securePassword
                ErrorAction = "Stop"
            }
            $cred = New-Object System.Management.Automation.PSCredential @splatCredential

            $splatInvokeTips = @{
                SqlInstance     = $TestConfig.azureserver
                Database        = "test"
                SqlCredential   = $cred
                ReturnAllTips   = $true
                EnableException = $true
            }
            $result = Invoke-DbaDbAzSqlTip @splatInvokeTips
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the correct properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "tip_id",
                "description",
                "confidence_percent",
                "additional_info_url",
                "details"
            )
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties[$prop] | Should -Not -BeNullOrEmpty -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has no Select-DefaultView properties" {
            $result[0].PSStandardMembers.DefaultDisplayPropertySet | Should -BeNullOrEmpty
        }
    }
}
