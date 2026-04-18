#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DecryptedObject",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Error handling" {
        It "Should route password query failures through Stop-Function" {
            InModuleScope "dbatools" {
                $typeData = Get-TypeData -TypeName "Microsoft.SqlServer.Management.Smo.Server"
                $originalQuery = $typeData.Members["Query"].Script
                $originalInvoke = $typeData.Members["Invoke"].Script
                $functionNames = @(
                    "Invoke-Command2",
                    "Resolve-DbaComputerName",
                    "Stop-Function",
                    "Write-Message"
                )
                $originalFunctions = @{ }

                foreach ($functionName in $functionNames) {
                    if (Test-Path "Function:\$functionName") {
                        $originalFunctions[$functionName] = (Get-Item -Path "Function:\$functionName").ScriptBlock
                    }
                }

                try {
                    function Invoke-Command2 { [byte[]](1..16) }
                    function Resolve-DbaComputerName { "sql1" }
                    function Stop-Function {
                        param(
                            $Message,
                            $Target,
                            $ErrorRecord
                        )

                        throw "$Message | inner: $($ErrorRecord.Exception.Message)"
                    }
                    function Write-Message { }

                    Update-TypeData -TypeName "Microsoft.SqlServer.Management.Smo.Server" -MemberType ScriptProperty -MemberName DomainInstanceName -Value { "sql1" } -Force
                    Update-TypeData -TypeName "Microsoft.SqlServer.Management.Smo.Server" -MemberType ScriptProperty -MemberName ServiceInstanceId -Value { "MSSQL16.SQL1" } -Force
                    Update-TypeData -TypeName "Microsoft.SqlServer.Management.Smo.Server" -MemberType ScriptMethod -MemberName Query -Value {
                        param($sql)

                        if ($sql -like "*sys.key_encryptions*") {
                            [PSCustomObject]@{
                                smk = [byte[]](1, 2, 3, 4)
                            }
                        } else {
                            throw "password query failed"
                        }
                    } -Force

                    $server = New-Object Microsoft.SqlServer.Management.Smo.Server "sql1"

                    { Get-DecryptedObject -SqlInstance $server -Type Credential } | Should -Throw "*Can't execute password query on sql1.*password query failed*"
                } finally {
                    Remove-TypeData -TypeName "Microsoft.SqlServer.Management.Smo.Server"
                    Update-TypeData -TypeName "Microsoft.SqlServer.Management.Smo.Server" -MemberType ScriptMethod -MemberName Query -Value $originalQuery
                    Update-TypeData -TypeName "Microsoft.SqlServer.Management.Smo.Server" -MemberType ScriptMethod -MemberName Invoke -Value $originalInvoke

                    foreach ($functionName in $functionNames) {
                        if ($originalFunctions.ContainsKey($functionName)) {
                            Set-Item -Path "Function:\$functionName" -Value $originalFunctions[$functionName]
                        } else {
                            Remove-Item -Path "Function:\$functionName" -ErrorAction Ignore
                        }
                    }
                }
            }
        }
    }
}