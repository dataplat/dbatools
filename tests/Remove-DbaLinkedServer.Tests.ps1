#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaLinkedServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "LinkedServer",
                "InputObject",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $splatInstance2 = @{
            SqlInstance = $TestConfig.instance2
        }
        $splatInstance3 = @{
            SqlInstance = $TestConfig.instance3
        }
        $instance2 = Connect-DbaInstance @splatInstance2
        $instance3 = Connect-DbaInstance @splatInstance3

        $linkedServerName1 = "dbatoolscli_LS1_$random"
        $linkedServerName2 = "dbatoolscli_LS2_$random"
        $linkedServerName3 = "dbatoolscli_LS3_$random"
        $linkedServerName4 = "dbatoolscli_LS4_$random"

        $splatLinkedServer1 = @{
            SqlInstance  = $instance2
            LinkedServer = $linkedServerName1
        }
        $splatLinkedServer2 = @{
            SqlInstance  = $instance2
            LinkedServer = $linkedServerName2
        }
        $splatLinkedServer3 = @{
            SqlInstance  = $instance2
            LinkedServer = $linkedServerName3
        }
        $splatLinkedServer4 = @{
            SqlInstance  = $instance2
            LinkedServer = $linkedServerName4
        }

        $linkedServer1 = New-DbaLinkedServer @splatLinkedServer1
        $linkedServer2 = New-DbaLinkedServer @splatLinkedServer2
        $linkedServer3 = New-DbaLinkedServer @splatLinkedServer3
        $linkedServer4 = New-DbaLinkedServer @splatLinkedServer4

        # Add error checking
        if (-not ($linkedServer1 -and $linkedServer2 -and $linkedServer3 -and $linkedServer4)) {
            Write-Error "Failed to create one or more linked servers"
        }

        $securePassword = ConvertTo-SecureString -String "s3cur3P4ssw0rd?" -AsPlainText -Force
        $loginName = "dbatoolscli_test_$random"

        $splatLogin = @{
            SqlInstance    = @($instance2, $instance3)
            Login          = $loginName
            SecurePassword = $securePassword
        }
        New-DbaLogin @splatLogin

        $newLinkedServerLogin = New-Object Microsoft.SqlServer.Management.Smo.LinkedServerLogin
        $newLinkedServerLogin.Parent = $linkedServer4
        $newLinkedServerLogin.Name = $loginName
        $newLinkedServerLogin.RemoteUser = $loginName
        $newLinkedServerLogin.SetRemotePassword(($securePassword | ConvertFrom-SecurePass))
        $newLinkedServerLogin.Create()

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $linkedServers = @($linkedServerName1, $linkedServerName2, $linkedServerName3, $linkedServerName4)
        $instance2.LinkedServers.Refresh()
        foreach ($ls in $linkedServers) {
            if ($instance2.LinkedServers.Name -contains $ls) {
                $instance2.LinkedServers[$ls].Drop($true)
            }
        }

        $splatRemoveLogin = @{
            SqlInstance = @($instance2, $instance3)
            Login       = $loginName
            Confirm     = $false
        }
        Remove-DbaLogin @splatRemoveLogin -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "ensure command works" {
        It "Removes a linked server" {
            $splatGetLinkedServer1 = @{
                SqlInstance  = $TestConfig.instance2
                LinkedServer = $linkedServerName1
            }
            $results = Get-DbaLinkedServer @splatGetLinkedServer1
            $results.Length | Should -Be 1

            $splatRemoveLinkedServer1 = @{
                SqlInstance  = $TestConfig.instance2
                LinkedServer = $linkedServerName1
                Confirm      = $false
            }
            Remove-DbaLinkedServer @splatRemoveLinkedServer1

            $results = Get-DbaLinkedServer @splatGetLinkedServer1
            $results | Should -BeNullOrEmpty
        }

        It "Tries to remove a non-existent linked server" {
            $splatRemoveNonExistent = @{
                SqlInstance     = $TestConfig.instance2
                LinkedServer    = $linkedServerName1
                Confirm         = $false
                WarningVariable = "warnings"
                WarningAction   = "SilentlyContinue"
            }
            Remove-DbaLinkedServer @splatRemoveNonExistent
            $warnings | Should -BeLike "*Linked server $linkedServerName1 does not exist on $($instance2.Name)"
        }

        It "Removes a linked server passed in via pipeline" {
            $splatGetLinkedServer2 = @{
                SqlInstance  = $TestConfig.instance2
                LinkedServer = $linkedServerName2
            }
            $results = Get-DbaLinkedServer @splatGetLinkedServer2
            $results.Length | Should -Be 1

            $splatGetPipelineLinkedServer = @{
                SqlInstance  = $instance2
                LinkedServer = $linkedServerName2
            }
            Get-DbaLinkedServer @splatGetPipelineLinkedServer | Remove-DbaLinkedServer -Confirm:$false

            $splatGetVerifyLinkedServer = @{
                SqlInstance  = $instance2
                LinkedServer = $linkedServerName2
            }
            $results = Get-DbaLinkedServer @splatGetVerifyLinkedServer
            $results | Should -BeNullOrEmpty
        }

        It "Removes a linked server using a server passed in via pipeline" {
            $splatGetLinkedServer3 = @{
                SqlInstance  = $TestConfig.instance2
                LinkedServer = $linkedServerName3
            }
            $results = Get-DbaLinkedServer @splatGetLinkedServer3
            $results.Length | Should -Be 1

            $splatRemovePipelineServer = @{
                LinkedServer = $linkedServerName3
                Confirm      = $false
            }
            $instance2 | Remove-DbaLinkedServer @splatRemovePipelineServer

            $splatGetVerifyLinkedServer3 = @{
                SqlInstance  = $instance2
                LinkedServer = $linkedServerName3
            }
            $results = Get-DbaLinkedServer @splatGetVerifyLinkedServer3
            $results | Should -BeNullOrEmpty
        }

        It "Tries to remove a linked server that still has logins" {
            $splatGetLinkedServer4 = @{
                SqlInstance  = $instance2
                LinkedServer = $linkedServerName4
            }
            $splatRemoveWithWarning = @{
                Confirm         = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $null = Get-DbaLinkedServer @splatGetLinkedServer4 | Remove-DbaLinkedServer @splatRemoveWithWarning
            $warn | Should -BeLike "*There are still remote logins or linked logins for the server*"
        }

        It "Removes a linked server that requires the -Force param" {
            $splatGetLinkedServer4Final = @{
                SqlInstance  = $instance2
                LinkedServer = $linkedServerName4
            }
            $splatRemoveWithForce = @{
                Confirm = $false
                Force   = $true
            }
            Get-DbaLinkedServer @splatGetLinkedServer4Final | Remove-DbaLinkedServer @splatRemoveWithForce

            $splatGetVerifyLinkedServer4 = @{
                SqlInstance  = $instance2
                LinkedServer = $linkedServerName4
            }
            $results = Get-DbaLinkedServer @splatGetVerifyLinkedServer4
            $results | Should -BeNullOrEmpty
        }
    }
}