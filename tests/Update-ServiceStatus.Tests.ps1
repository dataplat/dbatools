#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Update-ServiceStatus",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        BeforeAll {
            $password = ConvertTo-SecureString "pw" -AsPlainText -Force
            $script:credential = New-Object PSCredential("sqladmin", $password)
            $script:mockCimSession = [PSCustomObject]@{
                ComputerName = "sql1"
            }
        }

        BeforeEach {
            $script:service = [PSCustomObject]@{
                PSComputerName  = "sql1"
                ComputerName    = "sql1"
                ServiceName     = "MSSQLSERVER"
                InstanceName    = "MSSQLSERVER"
                ServiceType     = "Engine"
                ServicePriority = 1
                State           = "Stopped"
            }
            $script:service.PSObject.TypeNames.Insert(0, "dbatools.DbaSqlService")

            $script:newCimSessionCalls = @()
            $script:removedCimSessions = @()

            function Write-Message {
                param(
                    $Message,
                    $Level,
                    $Target
                )
            }
            function Select-DefaultView {
                param(
                    $Property
                )

                process {
                    $_
                }
            }
            function Get-DbaCmObject {
                param(
                    $ComputerName,
                    $Namespace,
                    $Query,
                    $Credential
                )

                [PSCustomObject]@{
                    Name      = "MSSQLSERVER"
                    State     = "Stopped"
                    StartMode = "Manual"
                }
            }
            function New-CimSession {
                param(
                    $ComputerName,
                    $Credential,
                    $SessionOption,
                    $ErrorAction
                )

                $script:newCimSessionCalls += [PSCustomObject]@{
                    ComputerName  = $ComputerName
                    Credential    = $Credential
                    SessionOption = $SessionOption
                }
                $script:mockCimSession
            }
            function Get-CimInstance {
                param(
                    $CimSession,
                    $Namespace,
                    $Query,
                    $InputObject
                )

                if ($Query -like "SELECT State FROM Win32_Service*") {
                    [PSCustomObject]@{
                        State = "Running"
                    }
                } else {
                    [PSCustomObject]@{
                        Name      = "MSSQLSERVER"
                        State     = "Stopped"
                        StartMode = "Manual"
                    }
                }
            }
            function Invoke-CimMethod {
                param(
                    $InputObject,
                    $MethodName
                )

                [PSCustomObject]@{
                    State       = "Running"
                    ReturnValue = 0
                }
            }
            function Remove-CimSession {
                param(
                    $CimSession,
                    $ErrorAction
                )

                $script:removedCimSessions += $CimSession
            }
            function Invoke-Parallel {
                param(
                    $ScriptBlock,
                    $Throttle,
                    [switch]$ImportVariables
                )

                process {
                    $_ | ForEach-Object $ScriptBlock
                }
            }
        }

        It "uses the supplied credential for worker CIM sessions and cleans them up" {
            $null = Update-ServiceStatus -InputObject $script:service -Action "start" -Credential $script:credential

            $script:newCimSessionCalls.Count | Should -Be 1
            $script:newCimSessionCalls[0].ComputerName | Should -Be "sql1"
            $script:newCimSessionCalls[0].Credential | Should -Be $script:credential
            $script:newCimSessionCalls[0].SessionOption | Should -Not -BeNullOrEmpty
            $script:removedCimSessions.Count | Should -Be 1
            $script:removedCimSessions[0] | Should -Be $script:mockCimSession
        }
    }
}