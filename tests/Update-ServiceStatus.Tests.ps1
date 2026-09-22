#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Update-ServiceStatus",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        # Everything is set up in BeforeEach, and nothing uses $script:. Inside InModuleScope, Pester runs
        # a BeforeAll in the script scope of the dbatools module itself, so every variable it assigns -
        # with or without the $script: prefix - lands in the module and outlives this file: the process
        # keeps the module, so every test file that runs afterwards sees it. A $credential left there
        # reached the mock parameter filter { $null -eq $Credential } of Set-DbaPrivilege.Tests.ps1, which
        # only defines the parameters the mocked command was called with and resolves everything else
        # through the scope chain, and that test failed whenever this file had run before it. A BeforeEach
        # runs in a scope of its own that ends with the test.
        BeforeEach {
            $password = ConvertTo-SecureString "pw" -AsPlainText -Force
            $credential = New-Object PSCredential("sqladmin", $password)
            $mockCimSession = [PSCustomObject]@{
                ComputerName = "sql1"
            }

            $service = [PSCustomObject]@{
                PSComputerName  = "sql1"
                ComputerName    = "sql1"
                ServiceName     = "MSSQLSERVER"
                InstanceName    = "MSSQLSERVER"
                ServiceType     = "Engine"
                ServicePriority = 1
                State           = "Stopped"
            }
            $service.PSObject.TypeNames.Insert(0, "dbatools.DbaSqlService")

            # The fake commands below record their calls. They run in scopes of their own, where an
            # assignment to a variable would create a local one, so they write into this hashtable instead.
            $recorded = @{
                NewCimSessionCalls = @()
                RemovedCimSessions = @()
            }

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

                $recorded.NewCimSessionCalls += [PSCustomObject]@{
                    ComputerName  = $ComputerName
                    Credential    = $Credential
                    SessionOption = $SessionOption
                }
                $mockCimSession
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

                $recorded.RemovedCimSessions += $CimSession
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
            $null = Update-ServiceStatus -InputObject $service -Action "start" -Credential $credential

            $recorded.NewCimSessionCalls.Count | Should -Be 1
            $recorded.NewCimSessionCalls[0].ComputerName | Should -Be "sql1"
            $recorded.NewCimSessionCalls[0].Credential | Should -Be $credential
            $recorded.NewCimSessionCalls[0].SessionOption | Should -Not -BeNullOrEmpty
            $recorded.RemovedCimSessions.Count | Should -Be 1
            $recorded.RemovedCimSessions[0] | Should -Be $mockCimSession
        }
    }
}