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
}

Describe $CommandName -Tag IntegrationTests {
    Context "When no database selection is given" {
        It "Warns once and does not connect to the instance" {
            # The begin block stops when neither -Database, -ExcludeDatabase nor -AllUserDatabases is given, but the
            # process block used to run anyway and connected to the instance, which added a second warning about the
            # instance not being an Azure SQL Database (#10655).
            $results = Invoke-DbaDbAzSqlTip -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            $WarnVar.Count | Should -Be 1
            $WarnVar | Should -BeLike "*You must specify databases*"
        }

        It "Throws with -EnableException" {
            $splatNoDatabase = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningAction   = "SilentlyContinue"
                EnableException = $true
            }
            { Invoke-DbaDbAzSqlTip @splatNoDatabase } | Should -Throw "*You must specify databases*"
        }
    }
}
