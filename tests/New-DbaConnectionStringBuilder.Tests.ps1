param($ModuleName = 'dbatools')

Describe "New-DbaConnectionStringBuilder" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaConnectionStringBuilder
        }
        It "Should have ConnectionString as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionString
        }
        It "Should have ApplicationName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ApplicationName
        }
        It "Should have DataSource as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter DataSource
        }
        It "Should have SqlCredential as a non-mandatory PSCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have InitialCatalog as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter InitialCatalog
        }
        It "Should have IntegratedSecurity as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter IntegratedSecurity
        }
        It "Should have UserName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter UserName
        }
        It "Should have Password as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Password
        }
        It "Should have MultipleActiveResultSets as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter MultipleActiveResultSets
        }
        It "Should have ColumnEncryptionSetting as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ColumnEncryptionSetting
        }
        It "Should have Legacy as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Legacy
        }
        It "Should have NonPooledConnection as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter NonPooledConnection
        }
        It "Should have WorkstationId as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter WorkstationId
        }
    }

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
        It "Should have an Application name of 'dbatools Powershell Module'" {
            $results.ApplicationName | Should -Be "dbatools Powershell Module"
        }
        It "Should have a Workstation ID of '${env:COMPUTERNAME}'" {
            $results.WorkstationID | Should -Be $env:COMPUTERNAME
        }
        It "Should have a null MultipeActiveRcordSets" {
            $results.MultipeActiveRcordSets | Should -BeNullOrEmpty
        }
    }

    Context "Assert that the default Application name is preserved" {
        BeforeAll {
            $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Initial Catalog=AlwaysEncryptedSample;UID=sa;PWD=alwaysB3Encrypt1ng;Application Name=Always Encrypted MvcString;Column Encryption Setting=enabled"
        }
        It "Should have the Application name of 'Always Encrypted MvcString'" {
            $results.ApplicationName | Should -Be "Always Encrypted MvcString"
        }
    }

    Context "Build a ConnectionStringBuilder by parameters" {
        BeforeAll {
            $results = New-DbaConnectionStringBuilder `
                -DataSource "localhost,1433" `
                -InitialCatalog "AlwaysEncryptedSample" `
                -UserName "sa" `
                -Password "alwaysB3Encrypt1ng"
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
        It "Should have a WorkstationID of ${env:COMPUTERNAME}" {
            $results.WorkstationID | Should -Be $env:COMPUTERNAME
        }
        It "Should have an Application name of 'dbatools Powershell Module'" {
            $results.ApplicationName | Should -Be "dbatools Powershell Module"
        }
        It "Should have a Workstation ID of '${env:COMPUTERNAME}'" {
            $results.WorkstationID | Should -Be ${env:COMPUTERNAME}
        }
    }

    Context "Explicitly set MARS to false" {
        BeforeAll {
            $results = New-DbaConnectionStringBuilder -MultipleActiveResultSets:$false
        }
        It "Should not enable Multiple Active Record Sets" {
            $results.MultipleActiveResultSets | Should -Be $false
        }
    }

    Context "Set MARS via alias" {
        BeforeAll {
            $results = New-DbaConnectionStringBuilder -MARS
        }
        It "Should have a MultipleActiveResultSets value of true" {
            $results.MultipleActiveResultSets | Should -Be $true
        }
    }

    Context "Set AlwaysEncrypted" {
        BeforeAll {
            $results = New-DbaConnectionStringBuilder -AlwaysEncrypted "Enabled"
        }
        It "Should have a 'Column Encryption Setting' value of 'Enabled'" {
            $results.ColumnEncryptionSetting | Should -Be 'Enabled'
        }
    }

    Context "Set IntegratedSecurity" {
        BeforeAll {
            $results = New-DbaConnectionStringBuilder -IntegratedSecurity
        }
        It "Should have an 'Integrated Security Setting' value of 'True'" {
            $results.IntegratedSecurity | Should -Be $True
        }
    }
}
