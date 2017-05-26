Describe "Get-DbaSqlConnectionStringBuilder Tests" {
    Context "Get a ConnectionStringBuilder and assert its values" {
        $results = Get-DbaSqlConnectionStringBuilder "Data Source=localhost,1433;Initial Catalog=AlwaysEncryptedSample;UID=sa;PWD=alwaysB3Encrypt1ng;Application Name=Always Encrypted MvcString;Column Encryption Setting=enabled" 
        It "Should be a connection string builder" {
            $results.GetType() | Should Be System.Data.SqlClient.SqlConnectionStringBuilder
        }
        It "Should enable Always Encrypted" {
            $results.ColumnEncryptionSetting  | Should Be "Enabled"
        }
        It "Should have a user name of sa" {
            $results.UserID  | Should Be "sa"
        }
    }
}