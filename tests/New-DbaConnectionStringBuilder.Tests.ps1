$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'ConnectionString', 'ApplicationName', 'DataSource', 'InitialCatalog', 'IntegratedSecurity', 'UserName', 'Password', 'MultipleActiveResultSets', 'ColumnEncryptionSetting', 'WorkstationId', 'Legacy', 'SqlCredential', 'NonPooledConnection', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Get a ConnectionStringBuilder and assert its values" {
        $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Initial Catalog=AlwaysEncryptedSample;UID=sa;PWD=alwaysB3Encrypt1ng;Column Encryption Setting=enabled"
        It "Should be a connection string builder" {
            $results.GetType() | Should -Be Microsoft.Data.SqlClient.SqlConnectionStringBuilder
        }
        It "Should enable Always Encrypted" {
            $results.ColumnEncryptionSetting | Should -Be Enabled
        }
        It "Should have a user name of sa" {
            $results.UserID | Should -Be "sa"
        }
        It "Should have an Application name of `"dbatools Powershell Module`"" {
            $results.ApplicationName | Should -Be "dbatools Powershell Module"
        }
        It "Should have an Workstation ID of `"${env:COMPUTERNAME}`"" {
            $results.WorkstationID | Should -Be $env:COMPUTERNAME
        }
        It "Should have a null MultipeActiveRcordSets" {
            $results.MultipeActiveRcordSets | Should -Be $null
        }
    }
    Context "Assert that the default Application name is preserved" {
        $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Initial Catalog=AlwaysEncryptedSample;UID=sa;PWD=alwaysB3Encrypt1ng;Application Name=Always Encrypted MvcString;Column Encryption Setting=enabled"
        It "Should have the Application name of `"Always Encrypted MvcString`"" {
            $results.ApplicationName | Should -Be "Always Encrypted MvcString"
        }
    }
    Context "Build a ConnectionStringBuilder by parameters" {
        $results = New-DbaConnectionStringBuilder `
            -DataSource "localhost,1433" `
            -InitialCatalog "AlwaysEncryptedSample" `
            -UserName "sa" `
            -Password "alwaysB3Encrypt1ng"
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
        It "Should have an Application name of `"dbatools Powershell Module`"" {
            $results.ApplicationName | Should -Be "dbatools Powershell Module"
        }
        It "Should have an Workstation ID of `"${env:COMPUTERNAME}`"" {
            $results.WorkstationID | Should -Be ${env:COMPUTERNAME}
        }
        It "Should have an InitialCatalog of `AlwaysEncryptedSample`"" {
            $results.InitialCatalog | Should -Be 'AlwaysEncryptedSample'
        }
    }
    Context "Explicitly set MARS to false" {
        $results = New-DbaConnectionStringBuilder `
            -MultipleActiveResultSets:$false
        It "Should not enable Multipe Active Record Sets" {
            $results.MultipleActiveResultSets | Should -Be $false
        }
    }
    Context "Set MARS via alias" {
        $results = New-DbaConnectionStringBuilder -MARS
        It "Should have a MultipeActiveResultSets value of true" {
            $results.MultipleActiveResultSets | Should -Be $true
        }
    }
    Context "Set AlwaysEncrypted" {
        $results = New-DbaConnectionStringBuilder -AlwaysEncrypted "Enabled"
        It "Should have a `"Column Encryption Setting`" value of `"Enabled`"" {
            $results.ColumnEncryptionSetting | Should -Be 'Enabled'
        }
    }
    Context "Set IntegratedSecurity" {
        $results = New-DbaConnectionStringBuilder -IntegratedSecurity
        It "Should have a `"Integrated Security Setting`" value of `"True`"" {
            $results.IntegratedSecurity | Should -Be $True
        }
        $results = New-DbaConnectionStringBuilder -IntegratedSecurity:$false
        It "Should have a `"Integrated Security Setting`" value of `"False`"" {
            $results.IntegratedSecurity | Should -Be $false
        }
    }

    Context "Can still return legacy builder" {
        $results = New-DbaConnectionStringBuilder -Legacy
        It "Should be a connection string builder" {
            $results.GetType() | Should -Be System.Data.SqlClient.SqlConnectionStringBuilder
        }
    }

    Context "Can use a SQL Credential" {
        $securePassword = ConvertTo-SecureString 'somepass' -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ('somelogin', $securePassword)
        $results = New-DbaConnectionStringBuilder -SqlCredential $cred
        It "Should have a user name of somelogin" {
            $results.UserID | Should -Be 'somelogin'
        }
        It "Should have a password of somepass" {
            $results.Password | Should -Be 'somepass'
        }
    }

    Context "Errors out for multiple 'credentials' passed in" {
        $securePassword = ConvertTo-SecureString 'somepass' -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ('somelogin', $securePassword)

        It "Should throw an error" {
            { New-DbaConnectionStringBuilder -Username 'test' -SqlCredential $cred -EnableException } | Should -Throw "You can only specify SQL Credential or Username/Password, not both"
        }
    }

    Context "Overrides (see #9606)" {
        Context "Workstation ID" {
            $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Workstation ID=mycomputer"
            It "Shouldn't override WorkstationId unless specified" {
                $results.WorkstationID | Should -Be 'mycomputer'
            }
            $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Workstation ID=mycomputer" -WorkstationID "another"
            It "Overrides WorkstationId when specified" {
                $results.WorkstationID | Should -Be 'another'
            }
        }

        Context "Integrated Security" {
            $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Integrated Security=False"
            It "Shouldn't override unless specified" {
                $results.IntegratedSecurity | Should -Be $False
            }
            $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Integrated Security=False" -IntegratedSecurity
            It "Overrides Integrated Security when specified" {
                $results.IntegratedSecurity | Should -Be $True
            }
        }

        Context "Pooling" {
            $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Pooling=False"
            It "Shouldn't override Pooling unless specified" {
                $results.Pooling | Should -Be $False
            }
            $results = New-DbaConnectionStringBuilder "Data Source=localhost,1433;Pooling=True" -NonPooledConnection
            It "Overrides Pooling when specified" {
                $results.Pooling | Should -Be $False
            }
        }
    }
}