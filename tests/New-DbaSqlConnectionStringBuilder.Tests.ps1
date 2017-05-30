Describe "New-DbaSqlConnectionStringBuilder Unit Tests" -Tag 'Unittests' {
    Context "Get a ConnectionStringBuilder and assert its values" {
        $results = New-DbaSqlConnectionStringBuilder "Data Source=localhost,1433;Initial Catalog=AlwaysEncryptedSample;UID=sa;PWD=alwaysB3Encrypt1ng;Column Encryption Setting=enabled" 
        It "Should be a connection string builder" {
            $results.GetType() | Should Be System.Data.SqlClient.SqlConnectionStringBuilder
        }
        It "Should enable Always Encrypted" {
            $results.ColumnEncryptionSetting  | Should Be "Enabled"
        }
        It "Should have a user name of sa" {
            $results.UserID  | Should Be "sa"
        }
        It "Should have an Application name of `"dbatools Powershell Module`"" {
            $results.ApplicationName  | Should Be "dbatools Powershell Module"
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
            $results.UserID  | Should Be "sa"
        }
        It "Should have an Application name of `"dbatools Powershell Module`"" {
            $results.ApplicationName  | Should Be "dbatools Powershell Module"
        }
    }
}