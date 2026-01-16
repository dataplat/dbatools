#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Update-DbaServiceAccount",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "InputObject",
                "ServiceName",
                "Username",
                "ServiceCredential",
                "PreviousPassword",
                "SecurePassword",
                "NoRestart",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # TODO: This test needs a lot of care
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $login = "winLogin"
        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $newPassword = 'Myxtr33mly$ecur3P@ssw0rd'
        $newSecurePassword = ConvertTo-SecureString $newPassword -AsPlainText -Force
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceRestart
        $computerName = $server.NetName
        $instanceName = $server.ServiceName
        $winLogin = "$computerName\$login"

        #Create Windows login
        $computer = [ADSI]"WinNT://$computerName"
        $user = $computer.Create("user", $login)
        $user.SetPassword($password)
        $user.SetInfo()

        #Get current service users
        $services = Get-DbaService -ComputerName $TestConfig.InstanceRestart -Type Engine, Agent -Instance $instanceName
        $currentAgentUser = ($services | Where-Object { $PSItem.ServiceType -eq "Agent" }).StartName
        $currentEngineUser = ($services | Where-Object { $PSItem.ServiceType -eq "Engine" }).StartName

        #Create a new sysadmin login on SQL Server
        $newLogin = New-Object Microsoft.SqlServer.Management.Smo.Login($server, $winLogin)
        $newLogin.LoginType = "WindowsUser"
        $newLogin.Create()
        $server.Roles["sysadmin"].AddMember($winLogin)
    }

    AfterAll {
        #Cleanup
        $server.Logins[$winLogin].Drop()
        $computer.Delete("User", $login)
    }

    Context "Set new service account for SQL Services" {
        BeforeAll {
            $cred = New-Object System.Management.Automation.PSCredential($login, $securePassword)
            $results = Update-DbaServiceAccount -ComputerName $computerName -ServiceName $services.ServiceName -ServiceCredential $cred
        }

        It "Should return something" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have no warnings" {
            # TODO: Why does Update-DbaServiceAccount outputs this warning?
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch [regex]::Escape('Invalid namespace: root\Microsoft\SQLServer\ReportServer') }
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Should be successful" {
            foreach ($result in $results) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
                $result.StartName | Should -Be ".\$login"
            }
        }
    }

    Context "Change password of the service account" {
        BeforeAll {
            #Change the password
            ([adsi]"WinNT://$computerName/$login,user").SetPassword($newPassword)

            $results = $services | Sort-Object ServicePriority | Update-DbaServiceAccount -Password $newSecurePassword
        }

        It "Password change should return something" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have no warnings" {
            # TODO: Why does Update-DbaServiceAccount outputs this warning?
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch [regex]::Escape('Invalid namespace: root\Microsoft\SQLServer\ReportServer') }
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Should be successful" {
            foreach ($result in $results) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
            }
        }
    }

    Context "Service restart validation" {
        BeforeAll {
            $results = Get-DbaService -ComputerName $computerName -ServiceName $services.ServiceName | Restart-DbaService
        }

        It "Service restart should return something" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Service restart should be successful" {
            foreach ($result in $results) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
            }
        }
    }

    Context "Change agent service account to local system" {
        BeforeAll {
            $results = $services | Where-Object { $PSItem.ServiceType -eq "Agent" } | Update-DbaServiceAccount -Username "NT AUTHORITY\LOCAL SYSTEM"
        }

        It "Should return something" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have no warnings" {
            # TODO: Why does Update-DbaServiceAccount outputs this warning?
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch [regex]::Escape('Invalid namespace: root\Microsoft\SQLServer\ReportServer') }
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Should be successful" {
            foreach ($result in $results) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
                $result.StartName | Should -Be "LocalSystem"
            }
        }
    }

    Context "Revert SQL Agent service account changes" {
        BeforeAll {
            $results = $services | Where-Object { $PSItem.ServiceType -eq "Agent" } | Update-DbaServiceAccount -Username $currentAgentUser
        }

        It "Should return something" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have no warnings" {
            # TODO: Why does Update-DbaServiceAccount outputs this warning?
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch [regex]::Escape('Invalid namespace: root\Microsoft\SQLServer\ReportServer') }
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Should be successful" {
            foreach ($result in $results) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
                $result.StartName | Should -Be $currentAgentUser
            }
        }
    }

    Context "Revert SQL Engine service account changes" {
        BeforeAll {
            $results = $services | Where-Object { $PSItem.ServiceType -eq "Engine" } | Update-DbaServiceAccount -Username $currentEngineUser
        }

        It "Should return something" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have no warnings" {
            # TODO: Why does Update-DbaServiceAccount outputs this warning?
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch [regex]::Escape('Invalid namespace: root\Microsoft\SQLServer\ReportServer') }
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Should be successful" {
            foreach ($result in $results) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
                $result.StartName | Should -Be $currentEngineUser
            }
        }
    }
}