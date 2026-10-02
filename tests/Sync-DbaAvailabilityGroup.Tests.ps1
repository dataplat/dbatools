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
                "UseJobLastModified",
                "InputObject",
                "ExcludePassword",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Connection behavior" {
        It "Should open one dedicated admin connection and share it with all password-aware copy commands" {
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
                        $script:dacConnections += $SqlInstance.Name
                        [PSCustomObject]@{
                            Name               = "ADMIN:$($SqlInstance.Name)"
                            DomainInstanceName = $SqlInstance.DomainInstanceName
                        }
                    } else {
                        [PSCustomObject]@{
                            Name               = $SqlInstance.ToString()
                            DomainInstanceName = $SqlInstance.ToString()
                        }
                    }
                }
                function Disconnect-DbaInstance {
                    [CmdletBinding(SupportsShouldProcess)]
                    param(
                        [Parameter(ValueFromPipeline)]
                        $InputObject
                    )

                    process {
                        $script:disconnectedConnections += $InputObject.Name
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
                function Copy-DbaDbMail {
                    param(
                        $Source,
                        $Destination,
                        $Credential,
                        [switch]$ExcludePassword,
                        [switch]$Force
                    )

                    $script:copyDbMailCall = [PSCustomObject]@{
                        Source = $Source
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
                        Source = $Source
                    }
                }

                $script:dacConnections = @()
                $script:disconnectedConnections = @()
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

                $null = Sync-DbaAvailabilityGroup -Primary "sql1" -Secondary "sql2" -Credential $credential -Exclude $exclude

                $script:dacConnections.Count | Should -Be 1
                $script:dacConnections[0] | Should -Be "sql1"
                $script:copyCredentialCall.Source.Name | Should -Be "ADMIN:sql1"
                $script:copyDbMailCall.Source.Name | Should -Be "ADMIN:sql1"
                $script:copyLinkedServerCall.Source.Name | Should -Be "ADMIN:sql1"
                $script:disconnectedConnections.Count | Should -Be 1
                $script:disconnectedConnections[0] | Should -Be "ADMIN:sql1"
                $script:copyCredentialCall.Credential.UserName | Should -Be "contoso\syncuser"
                $script:copyCredentialCall.ExcludePassword | Should -BeFalse
            }
        }

        It "Should reuse a dedicated admin connection that is already open and use a normal connection for the other commands" {
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
                        $script:dacConnections += $SqlInstance.Name
                    }

                    if ($SqlInstance.ToString() -eq "sql1") {
                        # Simulates a primary that the user has already connected to with -DedicatedAdminConnection
                        [PSCustomObject]@{
                            Name               = "ADMIN:sql1"
                            DomainInstanceName = "sql1.contoso.com"
                        }
                    } else {
                        [PSCustomObject]@{
                            Name               = $SqlInstance.ToString()
                            DomainInstanceName = $SqlInstance.ToString()
                        }
                    }
                }
                function Disconnect-DbaInstance {
                    [CmdletBinding(SupportsShouldProcess)]
                    param(
                        [Parameter(ValueFromPipeline)]
                        $InputObject
                    )

                    process {
                        $script:disconnectedConnections += $InputObject.Name
                    }
                }
                function Copy-DbaSpConfigure {
                    param(
                        $Source,
                        $Destination
                    )

                    $script:copySpConfigureCall = [PSCustomObject]@{
                        Source = $Source
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
                        Source = $Source
                    }
                }

                $script:dacConnections = @()
                $script:disconnectedConnections = @()
                $script:copySpConfigureCall = $null
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
                    "SystemTriggers"
                )

                $null = Sync-DbaAvailabilityGroup -Primary "sql1" -Secondary "sql2" -Exclude $exclude

                $script:dacConnections | Should -BeNullOrEmpty
                $script:copyCredentialCall.Source.Name | Should -Be "ADMIN:sql1"
                $script:copySpConfigureCall.Source.Name | Should -Be "sql1.contoso.com"
                $script:disconnectedConnections | Should -BeNullOrEmpty
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
                        # Sync-DbaAvailabilityGroup always passes -UseLastModified from -UseJobLastModified
                        [switch]$UseLastModified,
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
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Sync-DbaAvailabilityGroup accepts -Primary and -Secondary without an availability group, so two standalone
        # instances are enough to run the real AgentJob sync, including Copy-DbaAgentJob, against SQL Server.
        $jobName = "dbatoolsci_syncag_job_$(Get-Random)"

        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1 -Job $jobName
        $splatStep = @{
            SqlInstance = $TestConfig.InstanceCopy1
            Job         = $jobName
            StepName    = "step1"
            Subsystem   = "TransactSql"
            Database    = "master"
            Command     = "SELECT 1"
        }
        $null = New-DbaAgentJobStep @splatStep

        # Only the test job, and every object type except AgentJob, so nothing else is synced and no DAC is opened
        $splatSync = @{
            Primary            = $TestConfig.InstanceCopy1
            Secondary          = $TestConfig.InstanceCopy2
            Job                = $jobName
            UseJobLastModified = $true
            Exclude            = @(
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
        }

        # Read msdb on the secondary directly so assertions don't depend on cached SMO objects
        $splatDestJob = @{
            SqlInstance  = $TestConfig.InstanceCopy2
            Database     = "msdb"
            Query        = "
SELECT j.job_id, j.date_modified, s.command
FROM dbo.sysjobs AS j
INNER JOIN dbo.sysjobsteps AS s ON s.job_id = j.job_id
WHERE j.name = @jobName AND s.step_id = 1"
            SqlParameter = @{ jobName = $jobName }
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Pipe from Get so a job that never reached the secondary doesn't turn cleanup into a second failure
        $null = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Job $jobName | Remove-DbaAgentJob

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Agent job sync with -UseJobLastModified" {
        It "creates the job on the secondary when it does not exist" {
            $null = Sync-DbaAvailabilityGroup @splatSync

            $WarnVar | Should -BeNullOrEmpty
            $destJob = Invoke-DbaQuery @splatDestJob
            $destJob.command | Should -Be "SELECT 1"
        }

        It "leaves an identical job untouched on a repeated sync" {
            $before = Invoke-DbaQuery @splatDestJob
            $before.job_id | Should -Not -BeNullOrEmpty

            $null = Sync-DbaAvailabilityGroup @splatSync

            $WarnVar | Should -BeNullOrEmpty
            $after = Invoke-DbaQuery @splatDestJob
            $after.job_id | Should -Be $before.job_id
            $after.date_modified | Should -Be $before.date_modified
        }

        It "propagates a newer changed job definition from the primary" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # Guarantee the primary's change lands after the secondary's copy was made
            Start-Sleep -Seconds 2
            $splatChangeStep = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Job         = $jobName
                StepName    = "step1"
                Command     = "SELECT 2"
            }
            $null = Set-DbaAgentJobStep @splatChangeStep
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $null = Sync-DbaAvailabilityGroup @splatSync

            $WarnVar | Should -BeNullOrEmpty
            $destJob = Invoke-DbaQuery @splatDestJob
            $destJob.command | Should -Be "SELECT 2"
        }
    }
}
