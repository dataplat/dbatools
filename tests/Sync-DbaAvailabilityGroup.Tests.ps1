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
}