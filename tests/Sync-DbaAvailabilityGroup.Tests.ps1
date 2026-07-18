#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Sync-DbaAvailabilityGroup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Primary",
                "PrimarySqlCredential",
                "Secondary",
                "SecondarySqlCredential",
                "Credential",
                "AvailabilityGroup",
                "Exclude",
                "Login",
                "ExcludeLogin",
                "Job",
                "ExcludeJob",
                "DisableJobOnDestination",
                "InputObject",
                "ExcludePassword",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Connection behavior" {
        It "Should let Copy-DbaCredential manage dedicated admin connections" {
            InModuleScope "dbatools" {
                function Test-FunctionInterrupt { $false }
                function Write-ProgressHelper { }
                function Connect-DbaInstance {
                    param(
                        $SqlInstance,
                        $SqlCredential,
                        [switch]$DedicatedAdminConnection
                    )

                    if ($DedicatedAdminConnection) {
                        $script:dacConnections += $SqlInstance.ToString()
                    }

                    [PSCustomObject]@{
                        Name               = $SqlInstance.ToString()
                        DomainInstanceName = $SqlInstance.ToString()
                    }
                }
                function Copy-DbaCredential {
                    param(
                        $Source,
                        $Destination,
                        $Credential,
                        [switch]$ExcludePassword,
                        [switch]$Force
                    )

                    $script:copyCredentialCall = [PSCustomObject]@{
                        Source          = $Source
                        Destination     = $Destination
                        Credential      = $Credential
                        ExcludePassword = $ExcludePassword.IsPresent
                    }
                }

                $script:dacConnections = @()
                $script:copyCredentialCall = $null

                $exclude = @(
                    "AgentAlert",
                    "AgentCategory",
                    "AgentJob",
                    "AgentOperator",
                    "AgentProxy",
                    "AgentSchedule",
                    "CustomErrors",
                    "DatabaseMail",
                    "DatabaseOwner",
                    "LinkedServers",
                    "LoginPermissions",
                    "Logins",
                    "SpConfigure",
                    "SystemTriggers"
                )
                $securePassword = ConvertTo-SecureString "Password1!" -AsPlainText -Force
                $credential = New-Object System.Management.Automation.PSCredential("contoso\syncuser", $securePassword)

                $null = Sync-DbaAvailabilityGroup -Primary "sql1" -Secondary "sql2" -Credential $credential -Exclude $exclude

                $script:dacConnections | Should -BeNullOrEmpty
                $script:copyCredentialCall.Credential.UserName | Should -Be "contoso\syncuser"
                $script:copyCredentialCall.ExcludePassword | Should -BeFalse
            }
        }

        It "Should pass ExcludePassword to password-aware copy commands" {
            InModuleScope "dbatools" {
                function Test-FunctionInterrupt { $false }
                function Write-ProgressHelper { }
                function Connect-DbaInstance {
                    param(
                        $SqlInstance,
                        $SqlCredential,
                        [switch]$DedicatedAdminConnection
                    )

                    if ($DedicatedAdminConnection) {
                        $script:dacConnections += $SqlInstance.ToString()
                    }

                    [PSCustomObject]@{
                        Name               = $SqlInstance.ToString()
                        DomainInstanceName = $SqlInstance.ToString()
                    }
                }
                function Copy-DbaCredential {
                    param(
                        $Source,
                        $Destination,
                        $Credential,
                        [switch]$ExcludePassword,
                        [switch]$Force
                    )

                    $script:copyCredentialCall = [PSCustomObject]@{
                        Credential      = $Credential
                        ExcludePassword = $ExcludePassword.IsPresent
                    }
                }
                function Copy-DbaDbMail {
                    param(
                        $Source,
                        $Destination,
                        $Credential,
                        [switch]$ExcludePassword,
                        [switch]$Force
                    )

                    $script:copyDbMailCall = [PSCustomObject]@{
                        Credential      = $Credential
                        ExcludePassword = $ExcludePassword.IsPresent
                    }
                }
                function Copy-DbaLinkedServer {
                    param(
                        $Source,
                        $Destination,
                        $Credential,
                        [switch]$ExcludePassword,
                        [switch]$Force
                    )

                    $script:copyLinkedServerCall = [PSCustomObject]@{
                        Credential      = $Credential
                        ExcludePassword = $ExcludePassword.IsPresent
                    }
                }

                $script:dacConnections = @()
                $script:copyCredentialCall = $null
                $script:copyDbMailCall = $null
                $script:copyLinkedServerCall = $null

                $exclude = @(
                    "AgentAlert",
                    "AgentCategory",
                    "AgentJob",
                    "AgentOperator",
                    "AgentProxy",
                    "AgentSchedule",
                    "CustomErrors",
                    "DatabaseOwner",
                    "LoginPermissions",
                    "Logins",
                    "SpConfigure",
                    "SystemTriggers"
                )
                $securePassword = ConvertTo-SecureString "Password1!" -AsPlainText -Force
                $credential = New-Object System.Management.Automation.PSCredential("contoso\syncuser", $securePassword)

                $null = Sync-DbaAvailabilityGroup -Primary "sql1" -Secondary "sql2" -Credential $credential -ExcludePassword -Exclude $exclude

                $script:dacConnections | Should -BeNullOrEmpty
                $script:copyCredentialCall.Credential.UserName | Should -Be "contoso\syncuser"
                $script:copyCredentialCall.ExcludePassword | Should -BeTrue
                $script:copyDbMailCall.Credential.UserName | Should -Be "contoso\syncuser"
                $script:copyDbMailCall.ExcludePassword | Should -BeTrue
                $script:copyLinkedServerCall.Credential.UserName | Should -Be "contoso\syncuser"
                $script:copyLinkedServerCall.ExcludePassword | Should -BeTrue
            }
        }
    }

    Context "Agent job sync behavior" {
        It "Should request only local jobs and keep local jobs in category 1" {
            InModuleScope "dbatools" {
                function Test-FunctionInterrupt { $false }
                function Write-ProgressHelper { }
                function Connect-DbaInstance {
                    param(
                        $SqlInstance,
                        $SqlCredential,
                        [switch]$DedicatedAdminConnection
                    )

                    [PSCustomObject]@{
                        Name               = $SqlInstance.ToString()
                        DomainInstanceName = $SqlInstance.ToString()
                    }
                }
                function Get-DbaAgentJob {
                    param(
                        $SqlInstance,
                        $Job,
                        $ExcludeJob,
                        $Type
                    )

                    $script:getAgentJobCall = [PSCustomObject]@{
                        SqlInstance = $SqlInstance
                        Type        = $Type
                    }

                    [PSCustomObject]@{
                        Name       = "dbatoolsci_localjob"
                        JobType    = "Local"
                        CategoryID = 1
                    }
                }
                function Copy-DbaAgentJob {
                    param(
                        $Destination,
                        [switch]$Force,
                        [switch]$DisableOnDestination,
                        $InputObject
                    )

                    $script:copyAgentJobCall = [PSCustomObject]@{
                        Destination = $Destination
                        InputObject = $InputObject
                    }
                }

                $script:getAgentJobCall = $null
                $script:copyAgentJobCall = $null

                $exclude = @(
                    "AgentAlert",
                    "AgentCategory",
                    "AgentOperator",
                    "AgentProxy",
                    "AgentSchedule",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "DatabaseOwner",
                    "LinkedServers",
                    "LoginPermissions",
                    "Logins",
                    "SpConfigure",
                    "SystemTriggers"
                )

                $null = Sync-DbaAvailabilityGroup -Primary "sql1" -Secondary "sql2" -Exclude $exclude

                $script:getAgentJobCall.SqlInstance.Name | Should -Be "sql1"
                $script:getAgentJobCall.Type | Should -Be "Local"
                $script:copyAgentJobCall.InputObject.Name | Should -Be "dbatoolsci_localjob"
                $script:copyAgentJobCall.InputObject.JobType | Should -Be "Local"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: the sync itself copies logins, jobs, and related objects from the primary to
    # each secondary replica of a live Availability Group, which needs a real multi-replica AG - that
    # leg is DEFERRED-TO-AG01 per the coordinator AG policy (the mocked UnitTests above already pin
    # the credential/DAC/agent-job dispatch behavior). What IS characterizable on a standalone
    # instance is the two parameter guards the source runs before any connection: both fire
    # deterministically and are connection-independent (probe-verified). Both calls pass WhatIf as
    # belt-and-braces on this copy command, though the guards return before any gated action.
    BeforeAll {
        $random = Get-Random
    }

    Context "Guarding before the sync" {
        It "Warns once and returns nothing when neither Primary nor InputObject is supplied" {
            $splatNoInput = @{
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Sync-DbaAvailabilityGroup @splatNoInput)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must supply either -Primary or an Input Object"
        }

        It "Warns once and returns nothing when Primary is supplied without a Secondary or AvailabilityGroup" {
            $splatNoTarget = @{
                Primary         = $TestConfig.InstanceSingle
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Sync-DbaAvailabilityGroup @splatNoTarget)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must specify a secondary or an availability group."
        }
    }
}