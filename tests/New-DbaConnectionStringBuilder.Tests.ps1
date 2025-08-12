#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaConnectionStringBuilder",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ConnectionString",
                "ApplicationName",
                "DataSource",
                "InitialCatalog",
                "IntegratedSecurity",
                "UserName",
                "Password",
                "MultipleActiveResultSets",
                "ColumnEncryptionSetting",
                "WorkstationId",
                "Legacy",
                "SqlCredential",
                "NonPooledConnection",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Get a ConnectionStringBuilder and assert its values" {
        BeforeAll {
            $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Initial Catalog=AlwaysEncryptedSample;UID=sa;PWD=alwaysB3Encrypt1ng;Column Encryption Setting=enabled"
        }

        It "Should be a connection string builder" {
            $results.GetType() | Should -Be Microsoft.Data.SqlClient.SqlConnectionStringBuilder
        }
        It "Should enable Always Encrypted" {
            $results.ColumnEncryptionSetting | Should -Be Enabled
        }
        It "Should have a user name of sa" {
            $results.UserID | Should -Be "sa"
        }
        It "Should have an Application name of ""dbatools Powershell Module""" {
            $results.ApplicationName | Should -Be "dbatools Powershell Module"
        }
        It "Should have an Workstation ID of ""${env:COMPUTERNAME}""" {
            $results.WorkstationID | Should -Be $env:COMPUTERNAME
        }
        It "Should have a null MultipeActiveRcordSets" {
            $results.MultipeActiveRcordSets | Should -Be $null
        }
    }
    Context "Assert that the default Application name is preserved" {
        BeforeAll {
            $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Initial Catalog=AlwaysEncryptedSample;UID=sa;PWD=alwaysB3Encrypt1ng;Application Name=Always Encrypted MvcString;Column Encryption Setting=enabled"
        }

        It "Should have the Application name of ""Always Encrypted MvcString""" {
            $results.ApplicationName | Should -Be "Always Encrypted MvcString"
        }
    }
    Context "Build a ConnectionStringBuilder by parameters" {
        BeforeAll {
            $splatParameters = @{
                DataSource     = "localhost,1433"
                InitialCatalog = "AlwaysEncryptedSample"
                UserName       = "sa"
                Password       = "alwaysB3Encrypt1ng"
            }
            $results = New-DbaConnectionStringBuilder @splatParameters
        }

        It "Should be a connection string builder" {
            $results.GetType() | Should -Be Microsoft.Data.SqlClient.SqlConnectionStringBuilder
        }
        It "Should have a user name of sa" {
            $results.UserID | Should -Be "sa"
        }
        It "Should have a password of alwaysB3Encrypt1ng" {
            $results.Password | Should -Be "alwaysB3Encrypt1ng"
        }
        It "Should have a WorkstationID of {$env:COMPUTERNAME}" {
            $results.WorkstationID | Should -Be $env:COMPUTERNAME
        }
        It "Should have an Application name of ""dbatools Powershell Module""" {
            $results.ApplicationName | Should -Be "dbatools Powershell Module"
        }
        It "Should have an Workstation ID of ""${env:COMPUTERNAME}""" {
            $results.WorkstationID | Should -Be ${env:COMPUTERNAME}
        }
        It "Should have an InitialCatalog of ""AlwaysEncryptedSample""" {
            $results.InitialCatalog | Should -Be "AlwaysEncryptedSample"
        }
    }
    Context "Explicitly set MARS to false" {
        BeforeAll {
            $results = New-DbaConnectionStringBuilder -MultipleActiveResultSets:$false
        }

        It "Should not enable Multipe Active Record Sets" {
            $results.MultipleActiveResultSets | Should -Be $false
        }
    }
    Context "Set MARS via alias" {
        BeforeAll {
            $results = New-DbaConnectionStringBuilder -MARS
        }

        It "Should have a MultipeActiveResultSets value of true" {
            $results.MultipleActiveResultSets | Should -Be $true
        }
    }
    Context "Set AlwaysEncrypted" {
        BeforeAll {
            $results = New-DbaConnectionStringBuilder -AlwaysEncrypted "Enabled"
        }

        It "Should have a ""Column Encryption Setting"" value of ""Enabled""" {
            $results.ColumnEncryptionSetting | Should -Be "Enabled"
        }
    }
    Context "Set IntegratedSecurity" {
        It "Should have a ""Integrated Security Setting"" value of ""True""" {
            $results = New-DbaConnectionStringBuilder -IntegratedSecurity
            $results.IntegratedSecurity | Should -Be $true
        }
        It "Should have a ""Integrated Security Setting"" value of ""False""" {
            $results = New-DbaConnectionStringBuilder -IntegratedSecurity:$false
            $results.IntegratedSecurity | Should -Be $false
        }
    }

    Context "Can still return legacy builder" {
        BeforeAll {
            $results = New-DbaConnectionStringBuilder -Legacy
        }

        It "Should be a connection string builder" {
            $results.GetType() | Should -Be System.Data.SqlClient.SqlConnectionStringBuilder
        }
    }

    Context "Can use a SQL Credential" {
        BeforeAll {
            $securePassword = ConvertTo-SecureString "somepass" -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ("somelogin", $securePassword)
            $results = New-DbaConnectionStringBuilder -SqlCredential $cred
        }

        It "Should have a user name of somelogin" {
            $results.UserID | Should -Be "somelogin"
        }
        It "Should have a password of somepass" {
            $results.Password | Should -Be "somepass"
        }
    }

    Context "Errors out for multiple 'credentials' passed in" {
        BeforeAll {
            $securePassword = ConvertTo-SecureString "somepass" -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ("somelogin", $securePassword)
        }

        It "Should throw an error" {
            { New-DbaConnectionStringBuilder -Username "test" -SqlCredential $cred -EnableException } | Should -Throw "You can only specify SQL Credential or Username/Password, not both"
        }
    }

    Context "Overrides (see #9606)" {
        Context "Workstation ID" {
            It "Shouldn't override WorkstationId unless specified" {
                $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Workstation ID=mycomputer"
                $results.WorkstationID | Should -Be "mycomputer"
            }
            It "Overrides WorkstationId when specified" {
                $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Workstation ID=mycomputer" -WorkstationID "another"
                $results.WorkstationID | Should -Be "another"
            }
        }

        Context "Integrated Security" {
            It "Shouldn't override unless specified" {
                $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Integrated Security=False"
                $results.IntegratedSecurity | Should -Be $false
            }
            It "Overrides Integrated Security when specified" {
                $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Integrated Security=False" -IntegratedSecurity
                $results.IntegratedSecurity | Should -Be $true
            }
        }

        Context "Pooling" {
            It "Shouldn't override Pooling unless specified" {
                $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Pooling=False"
                $results.Pooling | Should -Be $false
            }
            It "Overrides Pooling when specified" {
                $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Pooling=True" -NonPooledConnection
                $results.Pooling | Should -Be $false
            }
        }
    }
}