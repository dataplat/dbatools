Analyze the Pester test files for the dbatools PowerShell module and perform the following migration tasks from Pester v4 to v5:

1. Move all test code into appropriate blocks:
   - Relocate any code outside of `It`, `BeforeAll`, `BeforeEach`, `AfterAll`, or `AfterEach` blocks into the correct locations.
   - Place file setup code into `BeforeAll` blocks at the beginning of each test file.

2. Update `Describe` and `Context` blocks:
   - Remove any test code directly in these blocks.
   - Ensure proper nesting of `Context` within `Describe`.

3. Refactor `Skip` conditions:
   - Move skip logic outside of `BeforeAll` blocks.
   - Use global read-only variables for skip conditions where appropriate.

4. Update `TestCases`:
   - Ensure TestCases are defined in a way that's compatible with Pester v5's discovery phase.

5. Update assertion syntax:
   - Replace `Should Be` with `Should -Be`.
   - Update other assertion operators as needed (e.g., `Should Throw` to `Should -Throw`).

6. Modify `InModuleScope` usage:
   - Remove `InModuleScope` from around `Describe` and `It` blocks.
   - Replace with `-ModuleName` parameter on `Mock` where possible.

7. Update `Invoke-Pester` calls:
   - Modify parameters to align with Pester v5's simple or advanced interface.

8. Adjust mocking syntax:
   - Update any mock definitions to Pester v5 syntax.

   Make these changes directly in the code. If you encounter any SQL Server-specific testing scenarios that require special handling, implement the necessary adjustments while maintaining the integrity of the tests.

9. EXAMPLE PESTER V5 TEST SCRIPT:

```powershell
param($ModuleName = 'dbatools')
Describe "Connect-DbaInstance" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Connect-DbaInstance
        }
        It "Requires SqlInstance as a Mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory -Alias 'ConnectionString'
        }
        It "Accepts SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Accepts Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String -DefaultValue "(Get-DbatoolsConfigValue -FullName 'sql.connection.database')"
        }
        It "Accepts ApplicationIntent as a parameter" {
            $CommandUnderTest | Should -HaveParameter ApplicationIntent -Type String
        }
        It "Accepts AzureUnsupported as a parameter" {
            $CommandUnderTest | Should -HaveParameter AzureUnsupported -Type Switch
        }
        It "Accepts BatchSeparator as a parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSeparator -Type String
        }
        It "Accepts ConnectTimeout as a parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectTimeout -Type int -DefaultValue "([Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout)"
        }
    }
    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }
        # -Skip parameter must be true for this to not run, so need to check for the environment variable to not be set to the dependent value
        Context "Connects to Azure" -Skip:([Environment]::GetEnvironmentVariable('azuredbpasswd') -ne "failstooften") {
            BeforeAll {
                $securePassword = ConvertTo-SecureString $env:azuredbpasswd -AsPlainText -Force
                $cred = New-Object System.Management.Automation.PSCredential ($script:azuresqldblogin, $securePassword)
            }
            It "Should login to Azure" {
                $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
                $s.Name | Should -Match 'psdbatools.database.windows.net'
                $s.DatabaseEngineType | Should -Be 'SqlAzureDatabase'
            }
            It "Should keep the same database context" {
                $s = Connect-DbaInstance -SqlInstance psdbatools.database.windows.net -SqlCredential $cred -Database test
                $results = Invoke-DbaQuery -SqlInstance $s -Query "select db_name() as dbName"
                $results.dbName | Should -Be 'test'
            }
        }
        Context "Connects passing server <_> to -SqlInstance" -ForEach $script:instance1,$script:instance2 {
            BeforeAll {
                $server = Connect-DbaInstance -SqlInstance $_ -ApplicationIntent ReadOnly
            }
            It "Returns the proper name" {
                $server.Name | Should -Be $_
            }
            It "Returns more than one database" {
                $server.Databases.Name.Count -gt 0 | Should -Be $true
            }
            It "Returns the connection with ApplicationIntent of ReadOnly" {
                $server.ConnectionContext.ConnectionString -match "Intent=ReadOnly" | Should -Be $true
            }
            It "Keeps the same database context" {
                $null = $server.Databases['msdb'].Tables.Count
                $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'master'
            }
            It "Sets StatementTimeout to 0" {
                $server = Connect-DbaInstance -SqlInstance $server -StatementTimeout 0
                $server.ConnectionContext.StatementTimeout | Should -Be 0
            }
        }
        Context "Connects using SqlInstance for <_> as a connection string [Windows]" -Skip:(-not $IsWindows) -ForEach $script:instance1,$script:instance2 {
            BeforeAll {
                $cnString = "Data Source=$_;Initial Catalog=tempdb;Integrated Security=True;Encrypt=False;Trust Server Certificate=True"
                $server = Connect-DbaInstance -SqlInstance $cnString
            }
            It "Connects using a connection string" {
                $server.Databases.Name | Should -Exist
            }
            It "PR8962: Ensure context is not changed when connection string is used" {
                $null = $server.Databases['msdb'].Tables.Count
                $server.ConnectionContext.ExecuteScalar("select db_name()") | Should -Be 'tempdb'
            }
            It "Connects to the SQL Server 2016 - Appveyor environment" -Skip:([Environment]::GetEnvironmentVariable('appveyor')) {
                $server = Connect-DbaInstance -SqlInstance "Data Source=$_$cnString"
                $server.Databases.Name | Should -Exist
            }
            It "sets ConnectionContext parameters that are provided" {
                $params = @{
                    'BatchSeparator'           = 'GO'
                    'ConnectTimeout'           = 1
                    'Database'                 = 'master'
                    'LockTimeout'              = 1
                    'MaxPoolSize'              = 20
                    'MinPoolSize'              = 1
                    'NetworkProtocol'          = 'TcpIp'
                    'PacketSize'               = 4096
                    'PooledConnectionLifetime' = 600
                    'WorkstationId'            = 'MadeUpServer'
                    'SqlExecutionModes'        = 'ExecuteSql'
                    'StatementTimeout'         = 0
                }
                $server = Connect-DbaInstance -SqlInstance $_ @params
                foreach ($param in $params.GetEnumerator()) {
                    if ($param.Key -eq 'Database') {
                        $propName = 'DatabaseName'
                    } else {
                        $propName = $param.Key
                    }
                    $server.ConnectionContext.$propName | Should -Be $param.Value
                }
            }
        }
        Context "Connects using newly created login" -ForEach $script:instance1, $script:instance2 {
            BeforeAll {
                $password = 'MyV3ry$ecur3P@ssw0rd'
                $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
                $server = Connect-DbaInstance -SqlInstance $_
                $login = "dbatoolscitestlogin"

                #Create login
                $newLogin = New-Object Microsoft.SqlServer.Management.Smo.Login($server, $login)
                $newLogin.LoginType = "SqlLogin"
                $newLogin.Create($password)

                <# Create connection using new login #>
                $cred = New-Object System.Management.Automation.PSCredential ($login, $securePassword)
                $serverNewLogin = Connect-DbaInstance -SqlInstance $_ -SqlCredential $cred -NonPooledConnection
            }
            AfterAll {
                Disconnect-DbaInstance -InputObject $serverNewLogin
                #Cleanup created login
                if ($l = $server.logins[$login]) {
                    if ($c = $l.EnumCredentials()) {
                        $l.DropCredential($c)
                    }
                    $l.Drop()
                }
            }
            It "Successful login using the new login" {
                $serverNewLogin.Name | Should -Be $_
            }
        }
    }
}
```

10. Leave in comments like "#$script:instance2 for appveyor" -- it's a debugging thing

11. Do not use the Legacy parameter set that adapts Pester 5 syntax to Pester 4 syntax. This parameter set is deprecated, and does not work 100%. The -Strict and -PesterOption parameters are ignored, and providing advanced configuration to -Path (-Script), and -CodeCoverage via a hash table does not work.

12. Analyze and update: --CMDNAME--

Make these changes directly in the code. If you encounter any SQL Server-specific testing scenarios that require special handling, implement the necessary adjustments while maintaining the integrity of the tests.

The parameters are as follows:

