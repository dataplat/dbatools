$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Get a ConnectionStringBuilder and assert its values" {
        $results = New-DbaSqlConnectionStringBuilder "Data Source=localhost,1433;Initial Catalog=AlwaysEncryptedSample;UID=sa;PWD=alwaysB3Encrypt1ng;Column Encryption Setting=enabled"
        It "Should be a connection string builder" {
            $results.GetType() | Should Be System.Data.SqlClient.SqlConnectionStringBuilder
        }
        It "Should enable Always Encrypted" {
            $results.ColumnEncryptionSetting | Should Be Enabled
        }
        It "Should have a user name of sa" {
            $results.UserID  | Should Be "sa"
        }
        It "Should have an Application name of `"dbatools Powershell Module`"" {
            $results.ApplicationName  | Should Be "dbatools Powershell Module"
        }
        It "Should have an Workstation ID of `"${env:COMPUTERNAME}`"" {
            $results.WorkstationID  | Should Be $env:COMPUTERNAME
        }
        It "Should have a null MultipeActiveRcordSets" {
            $results.MultipeActiveRcordSets  | Should Be $null
        }
    }
    Context "Assert that the default Application name is preserved" {
        $results = New-DbaSqlConnectionStringBuilder "Data Source=localhost,1433;Initial Catalog=AlwaysEncryptedSample;UID=sa;PWD=alwaysB3Encrypt1ng;Application Name=Always Encrypted MvcString;Column Encryption Setting=enabled"
        It "Should have the Application name of `"Always Encrypted MvcString`"" {
            $results.ApplicationName  | Should Be "Always Encrypted MvcString"
        }
    }
    Context "Build a ConnectionStringBuilder by parameters" {
        $results = New-DbaSqlConnectionStringBuilder `
            -DataSource "localhost,1433" `
            -InitialCatalog "AlwaysEncryptedSample" `
            -UserName "sa" `
            -Password "alwaysB3Encrypt1ng"
        It "Should be a connection string builder" {
            $results.GetType() | Should Be System.Data.SqlClient.SqlConnectionStringBuilder
        }
        It "Should have a user name of sa" {
            $results.UserID | Should Be "sa"
        }
        It "Should have a password of alwaysB3Encrypt1ng" {
            $results.Password | Should Be "alwaysB3Encrypt1ng"
        }
        It "Should have a WorkstationID of {$env:COMPUTERNAME}" {
            $results.WorkstationID | Should Be $env:COMPUTERNAME
        }
        It "Should have an Application name of `"dbatools Powershell Module`"" {
            $results.ApplicationName  | Should Be "dbatools Powershell Module"
        }
        It "Should have an Workstation ID of `"${env:COMPUTERNAME}`"" {
            $results.WorkstationID  | Should Be ${env:COMPUTERNAME}
        }
    }
    Context "Explicitly set MARS to false" {
        $results = New-DbaSqlConnectionStringBuilder `
            -MultipleActiveResultSets:$false
        It "Should not enable Multipe Active Record Sets" {
            $results.MultipleActiveResultSets | Should Be $false
        }
    }
    Context "Set MARS via alias" {
        $results = New-DbaSqlConnectionStringBuilder -MARS
        It "Should have a MultipeActiveResultSets value of true" {
            $results.MultipleActiveResultSets | Should Be $true
        }
    }
    Context "Set AlwaysEncrypted" {
        $results = New-DbaSqlConnectionStringBuilder -AlwaysEncrypted "Enabled"
        It "Should have a `"Column Encryption Setting`" value of `"Enabled`"" {
            $results.ColumnEncryptionSetting | Should Be 'Enabled'
        }
    }
}