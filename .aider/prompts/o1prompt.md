You are an expert in PowerShell and the Pester testing framework, specifically Pester v5. I have a suite of tests written in Pester v4 that need to be migrated to Pester v5, following our project's best practices.

**Our Requirements:**

- **Ensure you have Parameter Validation unit Tests:**
  - Use `Should -HaveParameter` to validate command parameters, including their types, default values, whether they are mandatory, and any aliases.
  - Each parameter should have its own `It` block within a `Context` that groups parameter validation tests.
- **Scoping and Execution:**
  - Use `BeforeAll`, `BeforeEach`, and `BeforeDiscovery` blocks appropriately to ensure variables are properly scoped and available where needed.
  - Place all test code inside `It`, `BeforeAll`, `BeforeEach`, `AfterAll`, or `AfterEach` blocks.
  - Avoid placing code directly inside `Describe` or `Context` blocks.
- **Use `-ForEach` and `-Skip` Correctly:**
  - Utilize `-ForEach` to iterate over multiple instances or scenarios.
  - Be cautious with `-Skip` conditions due to changes in the Discovery phase in Pester v5.
- **Assertions and Syntax:**
  - Use assertions that match our style, such as `Should -Be`, `Should -Exist`, `Should -Match`, and `Should -HaveParameter`.
  - Ensure `It` block descriptions are clear and descriptive.
- **Avoid Deprecated Features:**
  - Remove any deprecated or outdated practices from Pester v4.
  - Use the updated syntax and features introduced in Pester v5.
- **Leave in comments like `#$script:instance2 for appveyor` -- it's a debugging thing**

**Example of a Pester v4 Test Script:**

```powershell
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ApplicationIntent', 'AzureUnsupported'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count) | Should Be 0
        }
    }
    Context "Validate alias" {
        It "Should contain the alias: cdi" {
            (Get-Alias cdi) | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Connection is properly made using a string" {
        BeforeAll {
            $params = @{
                'BatchSeparator'           = 'GO'
                'ConnectTimeout'           = 1
                'Database'                 = 'tempdb'
                'LockTimeout'              = 1
                'MaxPoolSize'              = 20
                'MinPoolSize'              = 1
                'NetworkProtocol'          = 'TcpIp'
                'PacketSize'               = 4096
                'PooledConnectionLifetime' = 600
                'WorkstationId'            = 'MadeUpServer'
                'SqlExecutionModes'        = 'ExecuteSql'
                'StatementTimeout'         = 0
                'ApplicationIntent'        = 'ReadOnly'
            }
            $server = Connect-DbaInstance -SqlInstance $script:instance1 @params
        }

        It "Returns the proper name" {
            $server.Name | Should -Be $script:instance1
        }

        It "Sets ConnectionContext parameters that are provided" {
            foreach ($param in $params.GetEnumerator()) {
                if ($param.Key -eq 'Database') {
                    $propName = 'DatabaseName'
                } else {
                    $propName = $param.Key
                }
                $server.ConnectionContext.$propName | Should -Be $param.Value
            }
        }

        It "Returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "Returns the connection with ApplicationIntent of ReadOnly" {
            $server.ConnectionContext.ConnectionString | Should -Match "Intent=ReadOnly"
        }

        It "Keeps the same database context" {
            $null = $server.Databases['msdb'].Tables.Count
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'tempdb'
        }

        It "Sets StatementTimeout to 0" {
            $server.ConnectionContext.StatementTimeout | Should -Be 0
        }
    }

    Context "Connection is properly made using a connection string" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance "Data Source=$script:instance1;Initial Catalog=tempdb;Integrated Security=True"
        }

        It "Returns the proper name" {
            $server.Name | Should -Be $script:instance1
        }

        It "Returns more than one database" {
            $server.Databases.Name.Count | Should -BeGreaterThan 1
        }

        It "Keeps the same database context" {
            $null = $server.Databases['msdb'].Tables.Count
            $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'tempdb'
        }
    }
}
```

**Example of the Expected Pester v5 Test Script:**

```powershell
param($ModuleName = 'dbatools')

Describe "Connect-DbaInstance Tests" {
    BeforeDiscovery {
        . (Join-Path $PSScriptRoot 'constants.ps1')
    }

    Context "Validate Parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Connect-DbaInstance
            $ParametersToTest = @(
                @{ Name = 'SqlInstance'; Type = 'DbaInstanceParameter[]'; Mandatory = $true; Alias = 'ConnectionString' },
                @{ Name = 'SqlCredential'; Type = 'PSCredential' },
                @{ Name = 'Database'; Type = 'String'; DefaultValue = "(Get-DbatoolsConfigValue -FullName 'sql.connection.database')" },
                @{ Name = 'ApplicationIntent'; Type = 'String' },
                @{ Name = 'AzureUnsupported'; Type = 'Switch' }
            )
        }

        foreach ($param in $ParametersToTest) {
            $description = if ($param.Mandatory) {
                "Requires $($param.Name) as a mandatory parameter"
            } else {
                "Accepts $($param.Name) as a parameter"
            }

            It $description {
                $shouldCmd = $CommandUnderTest | Should -HaveParameter -Name $param.Name -Type $param.Type
                if ($param.Mandatory) {
                    $shouldCmd -Mandatory
                }
                if ($param.DefaultValue) {
                    $shouldCmd -DefaultValue $param.DefaultValue
                }
                if ($param.Alias) {
                    $shouldCmd -Alias $param.Alias
                }
            }
        }
    }

    Context "Command Usage Tests" {
        Context "Connection is properly made using a string" {
            BeforeAll {
                $params = @{
                    'BatchSeparator'           = 'GO'
                    'ConnectTimeout'           = 1
                    'Database'                 = 'tempdb'
                    'LockTimeout'              = 1
                    'MaxPoolSize'              = 20
                    'MinPoolSize'              = 1
                    'NetworkProtocol'          = 'TcpIp'
                    'PacketSize'               = 4096
                    'PooledConnectionLifetime' = 600
                    'WorkstationId'            = 'MadeUpServer'
                    'SqlExecutionModes'        = 'ExecuteSql'
                    'StatementTimeout'         = 0
                    'ApplicationIntent'        = 'ReadOnly'
                }
                $server = Connect-DbaInstance -SqlInstance $script:instance1 @params
            }

            It "Returns the proper name" {
                $server.Name | Should -Be $script:instance1
            }

            It "Sets ConnectionContext parameters that are provided" {
                foreach ($param in $params.GetEnumerator()) {
                    $propName = if ($param.Key -eq 'Database') { 'DatabaseName' } else { $param.Key }
                    $server.ConnectionContext.$propName | Should -Be $param.Value
                }
            }

            It "Returns more than one database" {
                $server.Databases.Name.Count | Should -BeGreaterThan 1
            }

            It "Returns the connection with ApplicationIntent of ReadOnly" {
                $server.ConnectionContext.ConnectionString | Should -Match "Intent=ReadOnly"
            }

            It "Keeps the same database context" {
                $null = $server.Databases['msdb'].Tables.Count
                $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'tempdb'
            }

            It "Sets StatementTimeout to 0" {
                $server.ConnectionContext.StatementTimeout | Should -Be 0
            }
        }

        Context "Connection is properly made using a connection string" {
            BeforeAll {
                $server = Connect-DbaInstance -SqlInstance "Data Source=$script:instance1;Initial Catalog=tempdb;Integrated Security=True"
            }

            It "Returns the proper name" {
                $server.Name | Should -Be $script:instance1
            }

            It "Returns more than one database" {
                $server.Databases.Name.Count | Should -BeGreaterThan 1
            }

            It "Keeps the same database context" {
                $null = $server.Databases['msdb'].Tables.Count
                $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'tempdb'
            }
        }
    }
}
```

**Instructions:**

- Convert the provided Pester v4 test script to Pester v5, following the structure, style, and best practices demonstrated in the example.
- Ensure all tests are updated to use Pester v5 syntax and features.
- Retain the original test logic and intent.
- Adjust variable scoping and initialization as per Pester v5 best practices.
- Use `param($ModuleName = 'dbatools')` at the beginning of the test file.
- Use `Should -HaveParameter` for parameter validation.
- Organize tests using `Describe`, `Context`, and `It` blocks appropriately.
