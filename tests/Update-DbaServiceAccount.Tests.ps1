#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName   = "dbatools",
    $CommandName = "Update-DbaServiceAccount",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

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

    BeforeAll {
        $login = "winLogin"
        $password = "MyV3ry$ecur3P@ssw0rd"
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $newPassword = "Myxtr33mly$ecur3P@ssw0rd"
        $newSecurePassword = ConvertTo-SecureString $newPassword -AsPlainText -Force
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $computerName = $server.NetName
        $instanceName = $server.ServiceName
        $winLogin = "$computerName\$login"

        #cleanup
        $computer = [ADSI]"WinNT://$computerName"
        try {
            $user = [ADSI]"WinNT://$computerName/$login,user"
            if ($user.Name -eq $login) {
                $computer.Delete("User", $login)
            }
        } catch { <#User does not exist #> }

        if ($l = Get-DbaLogin -SqlInstance $TestConfig.instance2 -Login $winLogin) {
            $results = $server.Query("IF EXISTS (SELECT * FROM sys.server_principals WHERE name = '$winLogin') EXEC sp_who '$winLogin'")
            foreach ($spid in $results.spid) {
                $null = $server.Query("kill $spid")
            }
            if ($c = $l.EnumCredentials()) {
                $l.DropCredential($c)
            }
            $l.Drop()
        }
        #Create Windows login
        $user = $computer.Create("user", $login)
        $user.SetPassword($password)
        $user.SetInfo()

        #Get current service users
        $services = Get-DbaService -ComputerName $TestConfig.instance2 -Type Engine, Agent -Instance $instanceName
        $currentAgentUser = ($services | Where-Object { $PSItem.ServiceType -eq "Agent" }).StartName
        $currentEngineUser = ($services | Where-Object { $PSItem.ServiceType -eq "Engine" }).StartName

        #Create a new sysadmin login on SQL Server
        $newLogin = New-Object Microsoft.SqlServer.Management.Smo.Login($server, $winLogin)
        $newLogin.LoginType = "WindowsUser"
        $newLogin.Create()
        $server.Roles["sysadmin"].AddMember($winLogin)

        $isRevertable = $true
        ForEach ($svcaccount in $currentAgentUser, $currentEngineUser) {
            if (! ($svcaccount.EndsWith("$") -or $svcaccount.StartsWith("NT AUTHORITY\") -or $svcaccount.StartsWith("NT Service\"))) {
                $isRevertable = $false
            }
        }
        #Do not continue with the test if current configuration cannot be rolled back
        if (!$isRevertable) {
            Throw "Current configuration cannot be rolled back - the test will not continue."
        }
    }

    AfterAll {
        #Cleanup
        $server.Logins[$winLogin].Drop()
        $computer.Delete("User", $login)
    }

    Context "Current configuration to be able to roll back" {
        It "Both agent and engine services must exist" {
            ($services | Measure-Object).Count | Should -Be 2
        }
        It "Current service accounts should be localsystem-like or MSA to allow for a rollback" {
            $isRevertable | Should -Be $true
        }
    }



    Context "Set new service account for SQL Services" {
        BeforeAll {
            $global:errVar = $global:warnVar = $null
            $cred = New-Object System.Management.Automation.PSCredential($login, $securePassword)
            $global:results = Update-DbaServiceAccount -ComputerName $computerName -ServiceName $services.ServiceName -ServiceCredential $cred -ErrorVariable global:errVar -WarningVariable global:warnVar
        }

        It "Should return something" {
            $global:results | Should -Not -Be $null
        }
        It "Should have no errors or warnings" {
            $global:errVar | Should -Be $null
            $global:warnVar | Should -Be $null
        }
        It "Should be successful" {
            foreach ($result in $global:results) {
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

            $global:errVarPw = $global:warnVarPw = $null
            $global:resultsPw = $services | Sort-Object ServicePriority | Update-DbaServiceAccount -Password $newSecurePassword -ErrorVariable global:errVarPw -WarningVariable global:warnVarPw
        }

        It "Password change should return something" {
            $global:resultsPw | Should -Not -Be $null
        }
        It "Should have no errors or warnings" {
            $global:errVarPw | Should -Be $null
            $global:warnVarPw | Should -Be $null
        }
        It "Should be successful" {
            foreach ($result in $global:resultsPw) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
            }
        }

        Context "Service restart validation" {
            BeforeAll {
                $global:resultsRestart = Get-DbaService -ComputerName $computerName -ServiceName $services.ServiceName | Restart-DbaService
            }

            It "Service restart should return something" {
                $global:resultsRestart | Should -Not -Be $null
            }
            It "Service restart should be successful" {
                foreach ($result in $global:resultsRestart) {
                    $result.Status | Should -Be "Successful"
                    $result.State | Should -Be "Running"
                }
            }
        }
    }

    Context "Change agent service account to local system" {
        BeforeAll {
            $global:errVarAgent = $global:warnVarAgent = $null
            $global:resultsAgent = $services | Where-Object { $PSItem.ServiceType -eq "Agent" } | Update-DbaServiceAccount -Username "NT AUTHORITY\LOCAL SYSTEM" -ErrorVariable global:errVarAgent -WarningVariable global:warnVarAgent
        }

        It "Should return something" {
            $global:resultsAgent | Should -Not -Be $null
        }
        It "Should have no errors or warnings" {
            $global:errVarAgent | Should -Be $null
            $global:warnVarAgent | Should -Be $null
        }
        It "Should be successful" {
            foreach ($result in $global:resultsAgent) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
                $result.StartName | Should -Be "LocalSystem"
            }
        }
    }
    Context "Revert SQL Agent service account changes ($currentAgentUser)" {
        BeforeAll {
            $global:errVarRevertAgent = $global:warnVarRevertAgent = $null
            $global:resultsRevertAgent = $services | Where-Object { $PSItem.ServiceType -eq "Agent" } | Update-DbaServiceAccount -Username $currentAgentUser -ErrorVariable global:errVarRevertAgent -WarningVariable global:warnVarRevertAgent
        }

        It "Should return something" {
            $global:resultsRevertAgent | Should -Not -Be $null
        }
        It "Should have no errors or warnings" {
            $global:errVarRevertAgent | Should -Be $null
            $global:warnVarRevertAgent | Should -Be $null
        }
        It "Should be successful" {
            foreach ($result in $global:resultsRevertAgent) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
                $result.StartName | Should -Be $currentAgentUser
            }
        }
    }
    Context "Revert SQL Engine service account changes ($currentEngineUser)" {
        BeforeAll {
            $global:errVarRevertEngine = $global:warnVarRevertEngine = $null
            $global:resultsRevertEngine = $services | Where-Object { $PSItem.ServiceType -eq "Engine" } | Update-DbaServiceAccount -Username $currentEngineUser -ErrorVariable global:errVarRevertEngine -WarningVariable global:warnVarRevertEngine
        }

        It "Should return something" {
            $global:resultsRevertEngine | Should -Not -Be $null
        }
        It "Should have no errors or warnings" {
            $global:errVarRevertEngine | Should -Be $null
            $global:warnVarRevertEngine | Should -Be $null
        }
        It "Should be successful" {
            foreach ($result in $global:resultsRevertEngine) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
                $result.StartName | Should -Be $currentEngineUser
            }
        }

    }

}